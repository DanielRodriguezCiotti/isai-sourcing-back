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
 * Extracts a single ZIP entry as a decoded string.
 */
function extractZipEntry(
  compressed: Uint8Array,
  name: string
): string | null {
  let result: string | null = null;
  const bytes = unzipSync(compressed, {
    filter: (file) => {
      if (file.name === name) {
        console.log(
          `[ZIP] extracting ${file.name} (${(file.originalSize / 1024).toFixed(0)}KB decompressed)`
        );
        return true;
      }
      return false;
    },
  });
  if (bytes[name]) {
    result = decoder.decode(bytes[name]);
  }
  return result;
}

/**
 * Extracts a single ZIP entry as raw bytes (no string decode).
 */
function extractZipEntryRaw(
  compressed: Uint8Array,
  name: string
): Uint8Array | null {
  const bytes = unzipSync(compressed, {
    filter: (file) => {
      if (file.name === name) {
        console.log(
          `[ZIP] extracting ${file.name} (${(file.originalSize / 1024).toFixed(0)}KB decompressed)`
        );
        return true;
      }
      return false;
    },
  });
  return bytes[name] ?? null;
}

/**
 * Extracts two ZIP entries as decoded strings in a single pass.
 */
function extractZipEntryPair(
  compressed: Uint8Array,
  name1: string,
  name2: string
): { first: string | null; second: string | null } {
  const want = new Set([name1, name2]);
  const bytes = unzipSync(compressed, {
    filter: (file) => {
      if (want.has(file.name)) {
        console.log(
          `[ZIP] extracting ${file.name} (${(file.originalSize / 1024).toFixed(0)}KB decompressed)`
        );
        return true;
      }
      return false;
    },
  });
  return {
    first: bytes[name1] ? decoder.decode(bytes[name1]) : null,
    second: bytes[name2] ? decoder.decode(bytes[name2]) : null,
  };
}

/**
 * Finds the ZIP path for the first sheet named "Companies*".
 */
function findCompaniesSheetPath(
  workbookXml: string,
  relsXml: string
): string {
  let match = workbookXml.match(
    /<sheet[^>]*?\sname="(Companies[^"]*)"[^>]*?\sr:id="([^"]+)"/s
  );
  if (!match) {
    match = workbookXml.match(
      /<sheet[^>]*?\sr:id="([^"]+)"[^>]*?\sname="(Companies[^"]*)"/s
    );
    if (!match) throw new Error("No sheet starting with 'Companies' found");
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
  return target;
}

/**
 * Parses the sheet XML into header cells and data cells grouped by column.
 * Stores only raw values (shared string indices or literal values) — resolution happens later.
 */
function collectSheetData(sheetXml: string): {
  headerCells: { col: string; type: string; rawValue: string }[];
  dataCells: Map<string, { type: string; rawValue: string }[]>;
  headerRow: number;
} {
  const HEADER_ROW = 6;
  const cellRegex =
    /<c\s+r="([A-Z]+)(\d+)"(?:[^>]*?\st="([^"]*)")?[^>]*?>(.*?)<\/c>/gs;

  const headerCells: { col: string; type: string; rawValue: string }[] = [];
  // Map from column → list of raw cell values in data rows
  const dataCells = new Map<string, { type: string; rawValue: string }[]>();

  let cellMatch;
  while ((cellMatch = cellRegex.exec(sheetXml)) !== null) {
    const [, col, rowStr, type, inner] = cellMatch;
    const row = parseInt(rowStr, 10);
    if (row < HEADER_ROW) continue;

    const vMatch = inner.match(/<v>([^<]*)<\/v>/);
    if (!vMatch) continue;

    if (row === HEADER_ROW) {
      headerCells.push({ col, type: type ?? "", rawValue: vMatch[1] });
    } else {
      // Only store data — we'll filter to the right column after resolving headers
      if (!dataCells.has(col)) dataCells.set(col, []);
      dataCells.get(col)!.push({ type: type ?? "", rawValue: vMatch[1] });
    }
  }

  return { headerCells, dataCells, headerRow: HEADER_ROW };
}

/**
 * Scans sharedStrings.xml raw bytes, only decoding strings at needed indices.
 * This avoids creating a ~71MB JS string — we only decode the small slices we need.
 */
function resolveSharedStringsByIndex(
  rawBytes: Uint8Array,
  neededIndices: Set<number>
): Map<number, string> {
  const result = new Map<number, string>();
  if (neededIndices.size === 0) return result;

  const maxNeeded = Math.max(...neededIndices);
  let siCount = -1;

  // Byte patterns for scanning
  // <si  = [0x3C, 0x73, 0x69]  (followed by > or space)
  // <t   = [0x3C, 0x74]        (followed by > or space)
  // </t> = [0x3C, 0x2F, 0x74, 0x3E]
  const LT = 0x3c; // <
  const GT = 0x3e; // >
  const SLASH = 0x2f; // /
  const S_LOW = 0x73; // s
  const I_LOW = 0x69; // i
  const T_LOW = 0x74; // t

  let i = 0;
  const len = rawBytes.length;

  while (i < len) {
    // Look for '<'
    if (rawBytes[i] !== LT) {
      i++;
      continue;
    }

    // Check for <si> or <si  (start of shared string item)
    if (
      i + 3 < len &&
      rawBytes[i + 1] === S_LOW &&
      rawBytes[i + 2] === I_LOW &&
      (rawBytes[i + 3] === GT || rawBytes[i + 3] === 0x20)
    ) {
      siCount++;
      if (siCount > maxNeeded) break; // no more needed indices

      if (neededIndices.has(siCount)) {
        // Find all <t>...</t> content within this <si>...</si> and concatenate
        let value = "";
        let j = i + 4;
        while (j < len) {
          // Look for </si>
          if (
            rawBytes[j] === LT &&
            j + 4 < len &&
            rawBytes[j + 1] === SLASH &&
            rawBytes[j + 2] === S_LOW &&
            rawBytes[j + 3] === I_LOW &&
            rawBytes[j + 4] === GT
          ) {
            break; // end of this <si>
          }
          // Look for <t> or <t ...>
          if (
            rawBytes[j] === LT &&
            j + 1 < len &&
            rawBytes[j + 1] === T_LOW &&
            (j + 2 >= len || rawBytes[j + 2] === GT || rawBytes[j + 2] === 0x20)
          ) {
            // Find the closing > of this <t...>
            let tEnd = j + 2;
            while (tEnd < len && rawBytes[tEnd] !== GT) tEnd++;
            tEnd++; // skip >
            // Now find </t>
            const contentStart = tEnd;
            let contentEnd = tEnd;
            while (contentEnd + 3 < len) {
              if (
                rawBytes[contentEnd] === LT &&
                rawBytes[contentEnd + 1] === SLASH &&
                rawBytes[contentEnd + 2] === T_LOW &&
                rawBytes[contentEnd + 3] === GT
              ) {
                break;
              }
              contentEnd++;
            }
            if (contentEnd > contentStart) {
              value += decoder.decode(
                rawBytes.subarray(contentStart, contentEnd)
              );
            }
            j = contentEnd + 4; // skip </t>
            continue;
          }
          j++;
        }
        result.set(siCount, value);
        if (result.size === neededIndices.size) break; // found all
        i = j;
        continue;
      }
      i += 4;
      continue;
    }
    i++;
  }

  console.log(
    `[INFO] resolved ${result.size}/${neededIndices.size} shared strings (scanned ${siCount + 1} entries)`
  );
  return result;
}

/**
 * Main extraction — two-round approach to avoid holding sharedStrings + sheet simultaneously.
 *
 * Round 1: metadata + sheet XML → identify domain column, collect needed shared string indices
 * Round 2: sharedStrings raw bytes only → resolve only needed indices at byte level
 */
function extractDomainsFromCompaniesSheet(
  compressed: Uint8Array
): string[] {
  console.log(
    `[INFO] file size: ${(compressed.byteLength / 1024 / 1024).toFixed(2)}MB`
  );

  // === Round 1: metadata + sheet XML ===
  logMemory("round 1: extracting metadata");
  const { first: workbookXml, second: relsXml } = extractZipEntryPair(
    compressed,
    "xl/workbook.xml",
    "xl/_rels/workbook.xml.rels"
  );
  if (!workbookXml || !relsXml) {
    throw new Error("Missing workbook.xml or relationships file");
  }
  logMemory("round 1: metadata done");

  const sheetPath = findCompaniesSheetPath(workbookXml, relsXml);

  logMemory("round 1: extracting sheet XML");
  let sheetXml: string | null = extractZipEntry(compressed, sheetPath);
  if (!sheetXml) throw new Error(`Sheet file ${sheetPath} not found in ZIP`);
  console.log(
    `[INFO] sheet XML size: ${(sheetXml.length / 1024 / 1024).toFixed(1)}MB`
  );
  logMemory("round 1: sheet extracted");

  // Parse the sheet: collect header cells + all data cells by column
  const { headerCells, dataCells } = collectSheetData(sheetXml);
  sheetXml = null; // free the sheet XML before loading sharedStrings
  logMemory("round 1: sheet parsed and freed");

  console.log(
    `[INFO] header has ${headerCells.length} columns, data has ${dataCells.size} columns`
  );

  // Collect ALL shared string indices we'll need (headers + all data columns)
  // We need headers to find which column is "Domain Name"
  const neededIndices = new Set<number>();
  for (const cell of headerCells) {
    if (cell.type === "s") {
      neededIndices.add(parseInt(cell.rawValue, 10));
    }
  }

  // We don't know which column is Domain Name yet (headers might be shared strings),
  // so we must resolve headers first. But to minimize shared string lookups,
  // we only add data-column indices AFTER identifying the right column.
  // Strategy: resolve header indices → find Domain Name column → then resolve data indices.

  // === Round 2a: resolve header shared strings ===
  logMemory("round 2a: extracting sharedStrings (raw bytes)");
  let ssRawBytes: Uint8Array | null = extractZipEntryRaw(
    compressed,
    "xl/sharedStrings.xml"
  );
  if (!ssRawBytes) {
    throw new Error("xl/sharedStrings.xml not found in ZIP");
  }
  console.log(
    `[INFO] sharedStrings raw size: ${(ssRawBytes.byteLength / 1024 / 1024).toFixed(1)}MB`
  );
  logMemory("round 2a: sharedStrings extracted");

  // Resolve only header indices first
  const headerStrings = resolveSharedStringsByIndex(ssRawBytes, neededIndices);
  logMemory("round 2a: headers resolved");

  // Find Domain Name column
  let domainCol: string | null = null;
  for (const cell of headerCells) {
    let value: string;
    if (cell.type === "s") {
      value = headerStrings.get(parseInt(cell.rawValue, 10)) ?? "";
    } else {
      value = cell.rawValue;
    }
    if (value.trim() === "Domain Name") {
      domainCol = cell.col;
      break;
    }
  }

  if (!domainCol) {
    throw new Error("'Domain Name' column not found in the header row");
  }
  console.log(`[INFO] "Domain Name" found in column ${domainCol}`);

  // Get data cells for the Domain Name column only
  const domainDataCells = dataCells.get(domainCol) ?? [];
  console.log(`[INFO] ${domainDataCells.length} data cells in column ${domainCol}`);

  // Collect shared string indices needed for data
  const dataIndices = new Set<number>();
  const directDomains = new Set<string>();
  for (const cell of domainDataCells) {
    if (cell.type === "s") {
      dataIndices.add(parseInt(cell.rawValue, 10));
    } else {
      const trimmed = cell.rawValue.trim();
      if (trimmed) directDomains.add(trimmed);
    }
  }

  // === Round 2b: resolve data shared strings ===
  logMemory("round 2b: resolving data shared strings");
  const dataStrings = resolveSharedStringsByIndex(ssRawBytes, dataIndices);
  ssRawBytes = null; // free
  logMemory("round 2b: done, sharedStrings freed");

  // Build final domain set
  const domains = new Set<string>(directDomains);
  for (const [, value] of dataStrings) {
    const trimmed = value.trim();
    if (trimmed) domains.add(trimmed);
  }

  console.log(`[INFO] extracted ${domains.size} unique domains`);
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
