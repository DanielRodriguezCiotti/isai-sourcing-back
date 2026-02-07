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

    console.log(`Creating onepager for company: ${company_id}`);

    // Load the Mistral API key from environment variables
    const mistralApiKey = Deno.env.get("MISTRAL_API_KEY");
    if (!mistralApiKey) {
      throw new Error("MISTRAL_API_KEY is not set");
    }

    console.log("MISTRAL_API_KEY loaded successfully");

    // Create the onepager content (will use company_id in the future)
    const content = "hello world";

    // Simulate processing time (e.g. calling Mistral API)
    await new Promise((resolve) => setTimeout(resolve, 10_000));

    // Return the generated text content
    return new Response(
      JSON.stringify({
        success: true,
        content,
        filename: "onepager.txt",
      }),
      {
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
        },
        status: 200,
      }
    );
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
