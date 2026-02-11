import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import * as XLSX from "https://cdn.sheetjs.com/xlsx-0.20.3/package/xlsx.mjs";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function logMemory(label: string) {
  const mem = Deno.memoryUsage();
  console.log(
    `[MEM] ${label} — heapUsed: ${(mem.heapUsed / 1024 / 1024).toFixed(1)}MB, heapTotal: ${(mem.heapTotal / 1024 / 1024).toFixed(1)}MB, rss: ${(mem.rss / 1024 / 1024).toFixed(1)}MB`
  );
}

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
    status,
  });
}

function extractDomainsFromCompaniesSheet(fileBuffer: ArrayBuffer): string[] {
  logMemory("before Uint8Array copy");
  const raw = new Uint8Array(fileBuffer);
  console.log(`[INFO] file size: ${(raw.byteLength / 1024 / 1024).toFixed(2)}MB`);

  // Pass 1: read only sheet names (no cell data parsed)
  logMemory("before bookSheets pass");
  const stub = XLSX.read(raw, { type: "array", bookSheets: true });
  console.log(`[INFO] sheets found: ${stub.SheetNames.join(", ")}`);
  logMemory("after bookSheets pass");

  const companiesSheetName = stub.SheetNames.find((name: string) =>
    name.startsWith("Companies")
  );

  if (!companiesSheetName) {
    throw new Error("No sheet starting with 'Companies' found in the file");
  }

  // Pass 2: parse only the target sheet in dense mode
  logMemory("before XLSX.read (single sheet, dense)");
  const workbook = XLSX.read(raw, {
    type: "array",
    sheets: [companiesSheetName],
    dense: true,
  });
  logMemory("after XLSX.read (single sheet, dense)");

  const sheet = workbook.Sheets[companiesSheetName];

  if (!sheet["!ref"]) {
    throw new Error("Companies sheet is empty");
  }

  const range = XLSX.utils.decode_range(sheet["!ref"]);
  console.log(
    `[INFO] sheet "${companiesSheetName}" range: ${range.e.r + 1} rows x ${range.e.c + 1} cols`
  );
  const HEADER_ROW = 5; // Row index 5 (6th row), matching Python's pd.read_excel(header=5)

  // Find the column index for "Domain Name" in the header row
  let domainCol = -1;
  const headerRowData = sheet["!data"]?.[HEADER_ROW];
  if (headerRowData) {
    for (let C = range.s.c; C <= range.e.c; ++C) {
      const cell = headerRowData[C];
      if (cell && String(cell.v).trim() === "Domain Name") {
        domainCol = C;
        break;
      }
    }
  }

  if (domainCol === -1) {
    throw new Error("'Domain Name' column not found in the header row");
  }

  console.log(
    `[INFO] "Domain Name" found at column index ${domainCol} (${XLSX.utils.encode_col(domainCol)})`
  );

  // Walk only the "Domain Name" column, starting from the row after the header
  logMemory("before column extraction");
  const domains = new Set<string>();
  const data = sheet["!data"];
  if (data) {
    for (let R = HEADER_ROW + 1; R <= range.e.r; ++R) {
      const cell = data[R]?.[domainCol];
      if (cell && typeof cell.v === "string" && cell.v.trim() !== "") {
        domains.add(cell.v.trim());
      }
    }
  }
  console.log(`[INFO] extracted ${domains.size} unique domains`);
  logMemory("after column extraction");

  return [...domains];
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { file_path } = await req.json();

    if (!file_path) {
      return jsonResponse(
        { success: false, error: "file_path is required" },
        400
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const bucketName = Deno.env.get("TRAXCN_EXPORTS_BUCKET_NAME");

    if (!bucketName) {
      throw new Error("TRAXCN_EXPORTS_BUCKET_NAME is not set");
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    logMemory("before storage download");
    const { data: fileData, error: downloadError } = await supabase.storage
      .from(bucketName)
      .download(file_path);
    logMemory("after storage download");

    if (downloadError || !fileData) {
      throw new Error(
        `Failed to download file '${file_path}': ${downloadError?.message}`
      );
    }

    // Block-scope the buffer so it becomes unreachable before the DB query
    let domains: string[];
    {
      const fileBuffer = await fileData.arrayBuffer();
      logMemory("after arrayBuffer()");
      domains = extractDomainsFromCompaniesSheet(fileBuffer);
    }
    logMemory("after extraction (buffer out of scope)");

    if (!domains.length) {
      return jsonResponse({
        success: true,
        number_of_companies_to_add: 0,
        number_of_companies_to_update: 0,
        new_domains: [],
        existing_domains: [],
      });
    }

    logMemory("before DB query");
    const { data: existingRecords, error: queryError } = await supabase
      .from("traxcn_companies")
      .select("domain_name")
      .in("domain_name", domains);
    logMemory("after DB query");

    if (queryError) {
      throw new Error(
        `Failed to query existing domains: ${queryError.message}`
      );
    }

    const existingDomains = new Set(
      existingRecords.map((r: { domain_name: string }) => r.domain_name)
    );
    const newDomains = domains.filter((d) => !existingDomains.has(d));

    return jsonResponse({
      success: true,
      number_of_companies_to_add: newDomains.length,
      number_of_companies_to_update: existingDomains.size,
      new_domains: newDomains,
      existing_domains: [...existingDomains],
    });
  } catch (error) {
    return jsonResponse({ success: false, error: error.message }, 500);
  }
});
