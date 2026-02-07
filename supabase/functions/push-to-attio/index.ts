import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Parse the request body to get company_id
    const { company_id } = await req.json();

    if (!company_id) {
      throw new Error("company_id is required");
    }

    console.log(`Processing push to Attio for company: ${company_id}`);

    // Load the Attio API key from environment variables
    const attioApiKey = Deno.env.get("ATTIO_API_KEY");
    if (!attioApiKey) {
      throw new Error("ATTIO_API_KEY is not set");
    }

    console.log("ATTIO_API_KEY loaded successfully");

    // Simulate processing time (e.g. calling Attio API)
    await new Promise((resolve) => setTimeout(resolve, 5_000));

    // Randomly return success or failure
    const isSuccess = Math.random() > 0.5;

    if (isSuccess) {
      return new Response(
        JSON.stringify({
          success: true,
          message: `Company ${company_id} successfully pushed to Attio`,
        }),
        {
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
          },
          status: 200,
        }
      );
    } else {
      return new Response(
        JSON.stringify({
          success: false,
          message: `Failed to push company ${company_id} to Attio. Please try again.`,
        }),
        {
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
          },
          status: 200, // Still 200 — this is a business-logic failure, not a server error
        }
      );
    }
  } catch (error) {
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message,
      }),
      {
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
        },
        status: 500,
      }
    );
  }
});
