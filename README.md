# ISAI Backend — Supabase Edge Functions

This repository contains Supabase Edge Functions for the ISAI project, with automatic deployment via GitHub Actions.

## Edge Functions

### `create-onepager`
Generates a onepager document. Called when the user clicks "Create OnePager" in the frontend. Returns text content that the frontend downloads as a `.txt` file.

- **Env var required:** `MISTRAL_API_KEY`
- **Method:** `POST`
- **Response:** `{ success: boolean, content: string, filename: string }`

### `push-to-attio`
Pushes a company to Attio CRM. Called when the user clicks "Push to Attio" in the frontend. Returns success or failure.

- **Env var required:** `ATTIO_API_KEY`
- **Method:** `POST`
- **Body:** `{ company_id: string }`
- **Response:** `{ success: boolean, message: string }`

## Setup & Deployment

See the [CD Setup Guide](#cd-setup-guide) below for connecting GitHub to Supabase for automatic deployments.

### CD Setup Guide

#### 1. Generate a Supabase Access Token
1. Go to [https://supabase.com/dashboard/account/tokens](https://supabase.com/dashboard/account/tokens)
2. Click **Generate new token**
3. Give it a name (e.g. `github-actions-deploy`)
4. Copy the token

#### 2. Get your Supabase Project ID
Your project ref is: `blfkamqmdmgkykcjyopd` (visible in your project URL)

#### 3. Add GitHub Secrets
1. Go to your GitHub repo → **Settings** → **Secrets and variables** → **Actions**
2. Add these two secrets:
   - `SUPABASE_ACCESS_TOKEN` — the token from step 1
   - `SUPABASE_PROJECT_ID` — `blfkamqmdmgkykcjyopd`

#### 4. Set Edge Function Secrets in Supabase
```bash
# Via Supabase Dashboard: Project Settings → Edge Functions → Secrets
# Or via CLI:
supabase secrets set MISTRAL_API_KEY=your-mistral-key --project-ref blfkamqmdmgkykcjyopd
supabase secrets set ATTIO_API_KEY=your-attio-key --project-ref blfkamqmdmgkykcjyopd
```

#### 5. Push to `main`
Every push to the `main` branch automatically deploys both edge functions via GitHub Actions. You can also trigger a manual deploy from the **Actions** tab.

## Local Development

```bash
# Start local Supabase
supabase start

# Serve functions locally
supabase functions serve --env-file .env
```

Create a `.env` file for local development:
```
MISTRAL_API_KEY=fake-mistral-key-for-testing
ATTIO_API_KEY=fake-attio-key-for-testing
```
