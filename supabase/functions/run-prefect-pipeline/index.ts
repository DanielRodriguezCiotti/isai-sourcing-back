import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
    status,
  });
}

function buildApiUrl(orgId: string, workspaceId: string): string {
  return `https://api.prefect.cloud/api/accounts/${orgId}/workspaces/${workspaceId}`;
}

function buildFlowRunUrl(
  orgId: string,
  workspaceId: string,
  flowRunId: string,
): string {
  return `https://app.prefect.cloud/account/${orgId}/workspace/${workspaceId}/runs/flow-run/${flowRunId}?preview=true&tab=logs`;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { supabase_file_path } = await req.json();

    if (!supabase_file_path) {
      return jsonResponse(
        { success: false, error: "supabase_file_path is required" },
        400,
      );
    }

    const prefectApiKey = Deno.env.get("PREFECT_API_KEY");
    const prefectOrg = Deno.env.get("PREFECT_ORG");
    const prefectWorkspace = Deno.env.get("PREFECT_WORKSPACE");
    const deploymentId = Deno.env.get("PREFECT_PIPELINE_DEPLOYMENT_ID");

    if (!prefectApiKey || !prefectOrg || !prefectWorkspace || !deploymentId) {
      throw new Error(
        "Missing required environment variables: PREFECT_API_KEY, PREFECT_ORG, PREFECT_WORKSPACE, PREFECT_PIPELINE_DEPLOYMENT_ID",
      );
    }

    const endpoint =
      `${buildApiUrl(prefectOrg, prefectWorkspace)}/deployments/${deploymentId}/create_flow_run`;

    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${prefectApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        parameters: { supabase_file_path },
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(
        `Prefect API error: ${response.status} ${errorText}`,
      );
    }

    const result = await response.json();

    return jsonResponse({
      success: true,
      flow_run_name: result.name,
      flow_run_url: buildFlowRunUrl(prefectOrg, prefectWorkspace, result.id),
    });
  } catch (error) {
    return jsonResponse({ success: false, error: error.message }, 500);
  }
});
