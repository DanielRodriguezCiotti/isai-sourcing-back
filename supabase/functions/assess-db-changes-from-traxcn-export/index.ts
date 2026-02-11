import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { inflateSync, Inflate } from "https://esm.sh/fflate@0.8.2";

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

// ── ZIP parsing utilities ──────────────────────────────────────────────

function readU16(b: Uint8Array, o: number): number {
  return b[o] | (b[o + 1] << 8);
}
function readU32(b: Uint8Array, o: number): number {
  return (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)) >>> 0;
}

interface ZipEntry {
  compressedSize: number;
  uncompressedSize: number;
  compressionMethod: number;
  localHeaderOffset: number;
}

function parseZipDirectory(buf: Uint8Array): Map<string, ZipEntry> {
  // Find End of Central Directory (scan backwards, max 65KB comment)
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 65557); i--) {
    if (buf[i] === 0x50 && buf[i + 1] === 0x4b && buf[i + 2] === 0x05 && buf[i + 3] === 0x06) {
      eocd = i;
      break;
    }
  }
  if (eocd === -1) throw new Error("ZIP EOCD not found");

  const totalEntries = readU16(buf, eocd + 10);
  const cdOffset = readU32(buf, eocd + 16);
  const entries = new Map<string, ZipEntry>();
  let pos = cdOffset;

  for (let e = 0; e < totalEntries; e++) {
    if (readU32(buf, pos) !== 0x02014b50) throw new Error("Bad CD entry");
    const compressionMethod = readU16(buf, pos + 10);
    const compressedSize = readU32(buf, pos + 20);
    const uncompressedSize = readU32(buf, pos + 24);
    const nameLen = readU16(buf, pos + 28);
    const extraLen = readU16(buf, pos + 30);
    const commentLen = readU16(buf, pos + 32);
    const localHeaderOffset = readU32(buf, pos + 42);
    const name = decoder.decode(buf.subarray(pos + 46, pos + 46 + nameLen));
    entries.set(name, { compressedSize, uncompressedSize, compressionMethod, localHeaderOffset });
    pos += 46 + nameLen + extraLen + commentLen;
  }
  return entries;
}

/** Copies the compressed payload for a ZIP entry (uses .slice() to detach from the original buffer). */
function copyEntryCompressed(buf: Uint8Array, entry: ZipEntry): Uint8Array {
  const off = entry.localHeaderOffset;
  if (readU32(buf, off) !== 0x04034b50) throw new Error("Bad local header");
  const nameLen = readU16(buf, off + 26);
  const extraLen = readU16(buf, off + 28);
  const dataStart = off + 30 + nameLen + extraLen;
  return buf.slice(dataStart, dataStart + entry.compressedSize); // .slice() copies
}

/** Decompresses a small entry synchronously and returns a string. */
function inflateEntryToString(buf: Uint8Array, entry: ZipEntry): string {
  const raw = copyEntryCompressed(buf, entry);
  const bytes = entry.compressionMethod === 8 ? inflateSync(raw) : raw;
  return decoder.decode(bytes);
}

// ── Metadata parsing ───────────────────────────────────────────────────

function findCompaniesSheetPath(workbookXml: string, relsXml: string): string {
  let m = workbookXml.match(/<sheet[^>]*?\sname="(Companies[^"]*)"[^>]*?\sr:id="([^"]+)"/s);
  if (!m) {
    m = workbookXml.match(/<sheet[^>]*?\sr:id="([^"]+)"[^>]*?\sname="(Companies[^"]*)"/s);
    if (!m) throw new Error("No sheet starting with 'Companies' found");
    m = [m[0], m[2], m[1]] as unknown as RegExpMatchArray;
  }
  const [, sheetName, rId] = m;
  const rel = relsXml.match(new RegExp(`Id="${rId}"[^>]*?Target="([^"]+)"`));
  if (!rel) throw new Error(`Relationship ${rId} not found`);
  let target = rel[1].replace(/^\//, "");
  if (!target.startsWith("xl/")) target = "xl/" + target;
  console.log(`[INFO] Companies sheet: "${sheetName}" → ${target}`);
  return target;
}

// ── Streaming sheet scanner ────────────────────────────────────────────
// Uses fflate's Inflate to decompress in chunks — never holds 93MB in memory.
// Collects: header cells + shared-string indices per column (compact).

function streamScanSheet(
  compressedData: Uint8Array,
  compressionMethod: number,
  headerRow: number
): {
  headerCells: { col: string; type: string; rawValue: string }[];
  ssIndicesByCol: Map<string, number[]>;
} {
  const headerCells: { col: string; type: string; rawValue: string }[] = [];
  const ssIndicesByCol = new Map<string, number[]>();
  const td = new TextDecoder();
  let carryOver = "";

  function processText(text: string, isFinal: boolean) {
    const combined = carryOver + text;
    const re = /<c\s+r="([A-Z]+)(\d+)"(?:[^>]*?\st="([^"]*)")?[^>]*?>(.*?)<\/c>/g;
    let lastEnd = 0;
    let match;

    while ((match = re.exec(combined)) !== null) {
      lastEnd = re.lastIndex;
      const [, col, rowStr, type, inner] = match;
      const row = parseInt(rowStr, 10);
      if (row < headerRow) continue;

      const v = inner.match(/<v>([^<]*)<\/v>/);
      if (!v) continue;

      if (row === headerRow) {
        headerCells.push({ col, type: type ?? "", rawValue: v[1] });
      } else if ((type ?? "") === "s") {
        // Only track shared-string cells (domains are always strings)
        if (!ssIndicesByCol.has(col)) ssIndicesByCol.set(col, []);
        ssIndicesByCol.get(col)!.push(parseInt(v[1], 10));
      }
    }

    if (isFinal) {
      carryOver = "";
    } else {
      const tail = combined.slice(lastEnd);
      const lt = tail.lastIndexOf("<");
      carryOver = lt >= 0 ? tail.slice(lt) : "";
    }
  }

  if (compressionMethod === 0) {
    processText(td.decode(compressedData), true);
  } else {
    const inf = new Inflate((chunk: Uint8Array, final: boolean) => {
      processText(td.decode(chunk, { stream: !final }), final);
    });
    inf.push(compressedData, true);
  }

  return { headerCells, ssIndicesByCol };
}

// ── SharedStrings byte-level resolver ──────────────────────────────────
// Scans raw bytes, only decodes strings at needed indices.

function resolveSharedStringsByIndex(
  rawBytes: Uint8Array,
  neededIndices: Set<number>
): Map<number, string> {
  const result = new Map<number, string>();
  if (neededIndices.size === 0) return result;

  const maxNeeded = Math.max(...neededIndices);
  let siCount = -1;
  const LT = 0x3c, GT = 0x3e, SLASH = 0x2f, S = 0x73, I = 0x69, T = 0x74;
  let i = 0;
  const len = rawBytes.length;

  while (i < len) {
    if (rawBytes[i] !== LT) { i++; continue; }

    // Match <si> or <si ...>
    if (i + 3 < len && rawBytes[i + 1] === S && rawBytes[i + 2] === I &&
        (rawBytes[i + 3] === GT || rawBytes[i + 3] === 0x20)) {
      siCount++;
      if (siCount > maxNeeded) break;

      if (neededIndices.has(siCount)) {
        let value = "";
        let j = i + 4;
        while (j < len) {
          if (rawBytes[j] === LT && j + 4 < len &&
              rawBytes[j + 1] === SLASH && rawBytes[j + 2] === S &&
              rawBytes[j + 3] === I && rawBytes[j + 4] === GT) break;
          if (rawBytes[j] === LT && j + 1 < len && rawBytes[j + 1] === T &&
              (j + 2 >= len || rawBytes[j + 2] === GT || rawBytes[j + 2] === 0x20)) {
            let tEnd = j + 2;
            while (tEnd < len && rawBytes[tEnd] !== GT) tEnd++;
            tEnd++;
            const cStart = tEnd;
            let cEnd = tEnd;
            while (cEnd + 3 < len) {
              if (rawBytes[cEnd] === LT && rawBytes[cEnd + 1] === SLASH &&
                  rawBytes[cEnd + 2] === T && rawBytes[cEnd + 3] === GT) break;
              cEnd++;
            }
            if (cEnd > cStart) value += decoder.decode(rawBytes.subarray(cStart, cEnd));
            j = cEnd + 4;
            continue;
          }
          j++;
        }
        result.set(siCount, value);
        if (result.size === neededIndices.size) break;
        i = j;
        continue;
      }
      i += 4;
      continue;
    }
    i++;
  }

  console.log(`[INFO] resolved ${result.size}/${neededIndices.size} shared strings (scanned ${siCount + 1} entries)`);
  return result;
}

// ── Main handler ───────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { file_path } = await req.json();
    if (!file_path) {
      return jsonResponse({ success: false, error: "file_path is required" }, 400);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const bucketName = Deno.env.get("TRAXCN_EXPORTS_BUCKET_NAME");
    if (!bucketName) throw new Error("TRAXCN_EXPORTS_BUCKET_NAME is not set");

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    logMemory("before storage download");
    const { data: fileData, error: downloadError } = await supabase.storage
      .from(bucketName)
      .download(file_path);
    logMemory("after storage download");

    if (downloadError || !fileData) {
      throw new Error(`Failed to download file '${file_path}': ${downloadError?.message}`);
    }

    // ── Step 1: Parse ZIP directory, extract compressed copies, free the 63MB buffer ──
    let zipBuffer: Uint8Array | null = new Uint8Array(await fileData.arrayBuffer());
    console.log(`[INFO] file size: ${(zipBuffer.byteLength / 1024 / 1024).toFixed(2)}MB`);
    logMemory("after arrayBuffer");

    const entries = parseZipDirectory(zipBuffer);
    console.log(`[INFO] ZIP entries: ${[...entries.keys()].join(", ")}`);

    // Decompress tiny metadata directly
    const wbEntry = entries.get("xl/workbook.xml");
    const relsEntry = entries.get("xl/_rels/workbook.xml.rels");
    if (!wbEntry || !relsEntry) throw new Error("Missing workbook metadata in ZIP");
    const sheetPath = findCompaniesSheetPath(
      inflateEntryToString(zipBuffer, wbEntry),
      inflateEntryToString(zipBuffer, relsEntry)
    );

    // Copy compressed payloads for the two large entries
    const sheetEntry = entries.get(sheetPath);
    const ssEntry = entries.get("xl/sharedStrings.xml");
    if (!sheetEntry) throw new Error(`${sheetPath} not found in ZIP`);
    if (!ssEntry) throw new Error("xl/sharedStrings.xml not found in ZIP");

    const sheetCompressed = copyEntryCompressed(zipBuffer, sheetEntry);
    const ssCompressed = copyEntryCompressed(zipBuffer, ssEntry);
    console.log(
      `[INFO] compressed copies — sheet: ${(sheetCompressed.length / 1024 / 1024).toFixed(1)}MB, ss: ${(ssCompressed.length / 1024 / 1024).toFixed(1)}MB`
    );

    // FREE THE 63MB BUFFER
    zipBuffer = null;
    logMemory("after freeing ZIP buffer");

    // ── Step 2: Stream-scan sheet (never holds 93MB in memory) ──
    logMemory("before sheet stream scan");
    const { headerCells, ssIndicesByCol } = streamScanSheet(
      sheetCompressed,
      sheetEntry.compressionMethod,
      6 // header row (1-indexed)
    );
    // sheetCompressed is no longer needed — let it be GC'd
    console.log(
      `[INFO] header: ${headerCells.length} cols, data columns with strings: ${ssIndicesByCol.size}`
    );
    logMemory("after sheet stream scan");

    // ── Step 3: Inflate sharedStrings, resolve only needed indices ──
    logMemory("before sharedStrings inflate");
    const ssBytes: Uint8Array = ssEntry.compressionMethod === 8
      ? inflateSync(ssCompressed)
      : ssCompressed;
    console.log(`[INFO] sharedStrings inflated: ${(ssBytes.byteLength / 1024 / 1024).toFixed(1)}MB`);
    logMemory("after sharedStrings inflate");

    // Resolve header indices → find Domain Name column
    const headerNeeded = new Set<number>();
    for (const cell of headerCells) {
      if (cell.type === "s") headerNeeded.add(parseInt(cell.rawValue, 10));
    }
    const headerStrings = resolveSharedStringsByIndex(ssBytes, headerNeeded);

    let domainCol: string | null = null;
    for (const cell of headerCells) {
      const value = cell.type === "s"
        ? (headerStrings.get(parseInt(cell.rawValue, 10)) ?? "")
        : cell.rawValue;
      if (value.trim() === "Domain Name") {
        domainCol = cell.col;
        break;
      }
    }
    if (!domainCol) throw new Error("'Domain Name' column not found in header row");
    console.log(`[INFO] "Domain Name" → column ${domainCol}`);

    // Resolve data indices for that column
    const domainIndices = ssIndicesByCol.get(domainCol) ?? [];
    console.log(`[INFO] ${domainIndices.length} data cells in column ${domainCol}`);

    const dataNeeded = new Set(domainIndices);
    const dataStrings = resolveSharedStringsByIndex(ssBytes, dataNeeded);
    logMemory("after resolving domain strings");

    // Build unique domains
    const domains = new Set<string>();
    for (const idx of domainIndices) {
      const v = dataStrings.get(idx);
      if (v) {
        const trimmed = v.trim();
        if (trimmed) domains.add(trimmed);
      }
    }
    const domainList = [...domains];
    console.log(`[INFO] extracted ${domainList.length} unique domains`);
    logMemory("after domain extraction");

    if (!domainList.length) {
      return jsonResponse({
        success: true,
        number_of_companies_to_add: 0,
        number_of_companies_to_update: 0,
        new_domains: [],
        existing_domains: [],
      });
    }

    // ── Step 4: DB query ──
    logMemory("before DB query");
    const { data: existingRecords, error: queryError } = await supabase
      .from("traxcn_companies")
      .select("domain_name")
      .in("domain_name", domainList);
    logMemory("after DB query");

    if (queryError) {
      throw new Error(`Failed to query existing domains: ${queryError.message}`);
    }

    const existingDomains = new Set(
      existingRecords.map((r: { domain_name: string }) => r.domain_name)
    );
    const newDomains = domainList.filter((d) => !existingDomains.has(d));

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
