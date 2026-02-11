import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { unzipSync } from "https://esm.sh/fflate@0.8.2";

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

const decoder = new TextDecoder();

/**
 * Reads only specific ZIP entries from an XLSX buffer using fflate's filter.
 * This avoids decompressing the entire archive (SheetJS's fatal flaw for large files).
 */
function extractZipEntries(
  compressed: Uint8Array,
  names: Set<string>
): Record<string, string> {
  const result: Record<string, string> = {};
  const bytes = unzipSync(compressed, {
    filter: (file) => {
      if (names.has(file.name)) {
        console.log(
          `[ZIP] extracting ${file.name} (${(file.originalSize / 1024).toFixed(0)}KB decompressed)`
        );
        return true;
      }
      return false;
    },
  });
  for (const name of names) {
    if (bytes[name]) {
      result[name] = decoder.decode(bytes[name]);
    }
  }
  return result;
}

/**
 * Parses xl/workbook.xml + xl/_rels/workbook.xml.rels to find the ZIP path
 * for the first sheet whose name starts with "Companies".
 */
function findCompaniesSheetPath(
  workbookXml: string,
  relsXml: string
): { sheetName: string; sheetPath: string } {
  // <sheet> attributes can appear in any order; try both orderings
  let match = workbookXml.match(
    /<sheet[^>]*?\sname="(Companies[^"]*)"[^>]*?\sr:id="([^"]+)"/s
  );
  if (!match) {
    match = workbookXml.match(
      /<sheet[^>]*?\sr:id="([^"]+)"[^>]*?\sname="(Companies[^"]*)"/s
    );
    if (!match) throw new Error("No sheet starting with 'Companies' found");
    // swap groups: match[1]=rId, match[2]=name → we want name first
    match = [match[0], match[2], match[1]] as unknown as RegExpMatchArray;
  }
  const [, sheetName, rId] = match;

  const relMatch = relsXml.match(
    new RegExp(`Id="${rId}"[^>]*?Target="([^"]+)"`)
  );
  if (!relMatch) throw new Error(`Relationship ${rId} not found`);

  let target = relMatch[1].replace(/^\//, "");
  if (!target.startsWith("xl/")) target = "xl/" + target;

  console.log(`[INFO] Companies sheet: "${sheetName}" → ${target}`);
  return { sheetName, sheetPath: target };
}

/**
 * Builds a shared-string lookup array from xl/sharedStrings.xml.
 * Only stores string values at their index — no DOM parsing.
 */
function parseSharedStrings(xml: string): string[] {
  const strings: string[] = [];
  // Each shared string is wrapped in <si>...</si>
  // Simple strings: <si><t>value</t></si>
  // Rich text: <si><r><t>part1</t></r><r><t>part2</t></r></si>
  const siRegex = /<si>(.*?)<\/si>/gs;
  let siMatch;
  while ((siMatch = siRegex.exec(xml)) !== null) {
    const inner = siMatch[1];
    // Concatenate all <t> fragments (handles both simple and rich text)
    let value = "";
    const tRegex = /<t[^>]*>([^<]*)<\/t>/g;
    let tMatch;
    while ((tMatch = tRegex.exec(inner)) !== null) {
      value += tMatch[1];
    }
    strings.push(value);
  }
  return strings;
}

/**
 * Extracts unique domain names from the target sheet XML.
 *
 * XLSX cell format: <c r="D7" t="s"><v>42</v></c>
 *   - r = cell reference (column letters + row number)
 *   - t = type ("s" = shared string index, "inlineStr" = inline, absent = number)
 *   - <v> = value (shared string index when t="s")
 *
 * Strategy:
 *   1. Scan header row (row 6) to find which column holds "Domain Name"
 *   2. Walk all data rows and collect values from that column only
 */
function extractDomainsFromSheetXml(
  sheetXml: string,
  sharedStrings: string[]
): string[] {
  const HEADER_ROW = 6; // 1-indexed (row 6 = Python header=5)

  // Extract all <c> cells with a regex. We capture:
  //   1. column letters  2. row number  3. optional type  4. inner content
  const cellRegex =
    /<c\s+r="([A-Z]+)(\d+)"(?:[^>]*?\st="([^"]*)")?[^>]*?>(.*?)<\/c>/gs;

  // First pass: find "Domain Name" column from header row
  let domainCol: string | null = null;
  const headerCells: { col: string; value: string }[] = [];
  let cellMatch;

  // We need to collect header cells first
  while ((cellMatch = cellRegex.exec(sheetXml)) !== null) {
    const [, col, rowStr, type, inner] = cellMatch;
    const row = parseInt(rowStr, 10);
    if (row < HEADER_ROW) continue;
    if (row > HEADER_ROW) break; // past header row, stop collecting headers

    // Resolve cell value
    const vMatch = inner.match(/<v>([^<]*)<\/v>/);
    if (!vMatch) continue;
    let value: string;
    if (type === "s") {
      value = sharedStrings[parseInt(vMatch[1], 10)] ?? "";
    } else {
      value = vMatch[1];
    }
    headerCells.push({ col, value: value.trim() });
  }

  for (const cell of headerCells) {
    if (cell.value === "Domain Name") {
      domainCol = cell.col;
      break;
    }
  }

  if (!domainCol) {
    throw new Error("'Domain Name' column not found in the header row");
  }

  console.log(`[INFO] "Domain Name" found in column ${domainCol}`);

  // Second pass: extract all values from the Domain Name column
  cellRegex.lastIndex = 0; // reset regex
  const domains = new Set<string>();

  while ((cellMatch = cellRegex.exec(sheetXml)) !== null) {
    const [, col, rowStr, type, inner] = cellMatch;
    const row = parseInt(rowStr, 10);
    if (row <= HEADER_ROW) continue;
    if (col !== domainCol) continue;

    const vMatch = inner.match(/<v>([^<]*)<\/v>/);
    if (!vMatch) continue;

    let value: string;
    if (type === "s") {
      value = sharedStrings[parseInt(vMatch[1], 10)] ?? "";
    } else if (type === "inlineStr") {
      const isMatch = inner.match(/<t[^>]*>([^<]*)<\/t>/);
      value = isMatch ? isMatch[1] : "";
    } else {
      value = vMatch[1];
    }

    const trimmed = value.trim();
    if (trimmed) domains.add(trimmed);
  }

  console.log(`[INFO] extracted ${domains.size} unique domains`);
  return [...domains];
}

/**
 * Main extraction: replaces SheetJS with fflate (selective ZIP) + regex XML parsing.
 * Memory profile: only the needed ZIP entries are decompressed, never the full archive.
 */
function extractDomainsFromCompaniesSheet(
  compressed: Uint8Array
): string[] {
  console.log(
    `[INFO] file size: ${(compressed.byteLength / 1024 / 1024).toFixed(2)}MB`
  );

  // Step 1: extract only metadata files (~1KB each)
  logMemory("step 1: extracting workbook metadata");
  const meta = extractZipEntries(
    compressed,
    new Set(["xl/workbook.xml", "xl/_rels/workbook.xml.rels"])
  );
  logMemory("step 1: done");

  const { sheetPath } = findCompaniesSheetPath(
    meta["xl/workbook.xml"],
    meta["xl/_rels/workbook.xml.rels"]
  );

  // Step 2: extract shared strings + target sheet only
  logMemory("step 2: extracting sharedStrings + sheet");
  const dataEntries = extractZipEntries(
    compressed,
    new Set(["xl/sharedStrings.xml", sheetPath])
  );
  logMemory("step 2: done");

  // Step 3: parse shared strings
  logMemory("step 3: parsing shared strings");
  const sharedStrings = parseSharedStrings(
    dataEntries["xl/sharedStrings.xml"] ?? ""
  );
  console.log(`[INFO] shared strings count: ${sharedStrings.length}`);
  logMemory("step 3: done");

  // Step 4: extract domains from sheet XML
  logMemory("step 4: extracting domains from sheet");
  const domains = extractDomainsFromSheetXml(
    dataEntries[sheetPath],
    sharedStrings
  );
  logMemory("step 4: done");

  return domains;
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

    let domains: string[];
    {
      const fileBuffer = await fileData.arrayBuffer();
      logMemory("after arrayBuffer()");
      const compressed = new Uint8Array(fileBuffer);
      domains = extractDomainsFromCompaniesSheet(compressed);
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
