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
    // Load the Mistral API key from environment variables
    const mistralApiKey = Deno.env.get("MISTRAL_API_KEY");
    if (!mistralApiKey) {
      throw new Error("MISTRAL_API_KEY is not set");
    }

    console.log("MISTRAL_API_KEY loaded successfully");

    // Create the onepager content
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
