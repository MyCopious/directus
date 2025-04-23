import { defineEndpoint } from "@directus/extensions-sdk";

export default defineEndpoint((router,context) => {
  
  router.get("/", (_req, res) => {
    res.json({ value: "Please use exact path to get the value of environment variable for e.g. /get_env/VITE_REDIRECT_CLIENT_URL where VITE_REDIRECT_CLIENT_URL is your environment variable \n For sercurity reasons only allowed environment variables are exposed with this API. If you need access to other environment variables, please modify within this api extension located at api/get_env/src/index.ts" });
  })
  router.get("/VITE_REDIRECT_CLIENT_URL", (_req, res) => {
    const redirectUrl = context.env.VITE_REDIRECT_CLIENT_URL || "";

    // Respond with JSON serialization
    res.json({ value: redirectUrl });
  });
});
