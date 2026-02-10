-- Initial migration: Create companies and funding_rounds tables
-- This migration creates the core tables for ISAI company tracking

-- Create the companies table
CREATE TABLE IF NOT EXISTS public.companies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  
  -- Basic company information
  logo TEXT,
  name TEXT NOT NULL,
  domain TEXT NOT NULL UNIQUE,
  hq_country TEXT,
  hq_city TEXT,
  inc_date INTEGER, -- Year only (YYYY)
  description TEXT, -- max 20 words enforced at application level
  all_tags TEXT[],

  -- Company metrics/info directly accessible
  vc_current_stage TEXT,
  total_amount_raised NUMERIC, -- Amount in millions USD
  last_funding_amount NUMERIC, -- Amount in millions USD
  last_funding_date DATE,
  all_investors TEXT[],

  -- Source of the company data
  source TEXT, -- "crunchbase" or "tracxn" or "both"

  -- Potential manual fields that can be filled by the user
  solution_fit_cg_manual INTEGER DEFAULT NULL,
  solution_fit_by_manual INTEGER DEFAULT NULL,
  business_fit_cg_manual INTEGER,
  business_fit_by_manual INTEGER,
  maturity_fit_manual INTEGER,
  equity_score_manual INTEGER,
  traction_score_manual INTEGER,
  global_fund_score_manual INTEGER
);


COMMENT ON TABLE public.companies IS
  'Core company table aggregating data from Crunchbase and Tracxn. Each row represents a unique company tracked by ISAI. We do reconciliation based on the domain. Sometimes, we have both sources and sometimes only one.';

COMMENT ON COLUMN public.companies.id IS
  'Unique identifier for the company record. Auto-generated UUID.';

COMMENT ON COLUMN public.companies.created_at IS
  'Timestamp when the company record was first created in the database.';

COMMENT ON COLUMN public.companies.updated_at IS
  'Timestamp of the last modification to the company record. Automatically updated via trigger.';

COMMENT ON COLUMN public.companies.logo IS
  'URL pointing to the company logo image. Source: CB (organizations.csv → logo_url). Crunchbase only — not available in Tracxn.';

COMMENT ON COLUMN public.companies.name IS
  'Official company name. Sources: CB (organizations.csv → name), Tracxn (Companies Covered 1.1 → Company Name). Priority: Tracxn.';

COMMENT ON COLUMN public.companies.domain IS
  'Main company domain name. Sources: CB (organizations.csv → domain), Tracxn (Companies Covered 1.1 → Domain Name). Priority: Tracxn.';

COMMENT ON COLUMN public.companies.hq_country IS
  'Country where the company headquarters is located. Sources: CB (organizations.csv → country_code), Tracxn (Companies Covered 1.1 → Country). Priority: Tracxn.';

COMMENT ON COLUMN public.companies.hq_city IS
  'City where the company headquarters is located. Sources: CB (organizations.csv → city), Tracxn (Companies Covered 1.1 → City). Priority: Tracxn.';

COMMENT ON COLUMN public.companies.inc_date IS
  'Year the company was founded (YYYY format, stored as integer). Sources: CB (organizations.csv → founded_on), Tracxn (Companies Covered 1.1 → Founded Year). Priority: Tracxn.';

COMMENT ON COLUMN public.companies.description IS
  'Short company description, max 20 words (enforced at application level). Sources: CB (organizations.csv → short_description), Tracxn (Companies Covered 1.1 → Description). Priority: Tracxn.';

COMMENT ON COLUMN public.companies.all_tags IS
  'Aggregated tags describing the company sector, business model, and classification. Sources: CB (organizations.csv → category_list + category_groups_list), Tracxn (Companies Covered 1.1 → Sector/Practice Area/Feed + Business Models + Waves + Special Flags). Priority: Tracxn + CB combined.';

COMMENT ON COLUMN public.companies.vc_current_stage IS
  'Current venture capital stage of the company (e.g. Seed, Series A, Series B…). Sources: Tracxn (Companies Covered 1.1 → Company Stage). Priority: Tracxn because value not directly available in crunchbase';

COMMENT ON COLUMN public.companies.total_amount_raised IS
  'Total cumulative funding raised by the company, in millions USD. Sources: CB (organizations.csv → total_funding_usd), Tracxn (Companies Covered 1.1 → Total Funding (USD)). Priority: CB + Tracxn cross-referenced (use both if values differ).';

COMMENT ON COLUMN public.companies.last_funding_amount IS
  'Amount raised in the most recent funding round, in millions USD. Sources: Tracxn (Companies Covered 1.1 → Latest Funded Amount (USD)). Priority: Tracxn because not directly available in CB';

COMMENT ON COLUMN public.companies.last_funding_date IS
  'Date of the most recent funding round in MM/YYYY format. Sources: CB (organizations.csv → last_funding_on), Tracxn (Companies Covered 1.1 → Latest Funded Date). Priority: CB + Tracxn cross-referenced (use both if values differ).';

COMMENT ON COLUMN public.companies.all_investors IS
  'List of all institutional investors in the company, max 50 words (enforced at application level). Source: Tracxn only (Companies Covered 1.1 → Institutional Investors). Not available in Crunchbase.';

COMMENT ON COLUMN public.companies.headcount IS
  'Current total number of employees. Sources: CB (organizations.csv → employee_count), Tracxn (Companies Covered 1.1 → Total Employee Count). Priority: Tracxn.';

-- Create the funding_rounds table
CREATE TABLE IF NOT EXISTS public.funding_rounds (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),

  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  date DATE,
  stage TEXT, -- e.g. Seed, Series A, Series B…
  amount NUMERIC, -- Amount in millions
  lead_investors TEXT[],
  all_investors TEXT[],
  source TEXT -- "cb" or "tracxn"
);

-- funding_rounds column descriptions
COMMENT ON TABLE public.funding_rounds IS
  'Individual funding rounds for each company. Sources: CB (funding_rounds.csv), Tracxn (Funding Rounds 2.1). One row per round per company. For this table, there is no reconciliation, we store all data from both sources.';

COMMENT ON COLUMN public.funding_rounds.id IS
  'Unique identifier for the funding round record. Auto-generated UUID.';

COMMENT ON COLUMN public.funding_rounds.created_at IS
  'Timestamp when the funding round record was first created in the database.';

COMMENT ON COLUMN public.funding_rounds.updated_at IS
  'Timestamp of the last modification to the funding round record. Automatically updated via trigger.';

COMMENT ON COLUMN public.funding_rounds.company_id IS
  'Foreign key referencing the company this funding round belongs to. Cascades on delete.';

COMMENT ON COLUMN public.funding_rounds.date IS
  'Date the funding round was announced. Sources: CB (funding_rounds.csv → announced_on), Tracxn (Funding Rounds 2.1 → Round Date).';

COMMENT ON COLUMN public.funding_rounds.stage IS
  'Type/stage of the funding round (e.g. Seed, Series A, Series B, Series C…). Sources: CB (funding_rounds.csv → investment_type), Tracxn (Funding Rounds 2.1 → Round Type).';

COMMENT ON COLUMN public.funding_rounds.amount IS
  'Amount raised in this funding round, in millions USD. Sources: CB (funding_rounds.csv → raised_amount_usd), Tracxn (Funding Rounds 2.1 → Round Amount (USD)).';

COMMENT ON COLUMN public.funding_rounds.lead_investors IS
  'Lead investor(s) for this funding round. Sources: CB (investors.csv → matched from lead_investor_uuids), Tracxn (Funding Rounds 2.1 → Lead Investor).';

COMMENT ON COLUMN public.funding_rounds.all_investors IS
  'All investors participating in this funding round. Sources: CB (funding_rounds.csv → investor_uuids matched to investor names), Tracxn (Funding Rounds 2.1 → Investors).';

COMMENT ON COLUMN public.funding_rounds.source IS
  'Source of the funding round data. "crunchbase" for Crunchbase, "tracxn" for Tracxn.';

-- Create the founders table
CREATE TABLE IF NOT EXISTS public.founders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),

  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  role TEXT, -- e.g. Founder, Co-founder, CEO & Founder
  description TEXT, 
  linkedin_url TEXT,
  source TEXT -- "crunchbase" or "tracxn"
);

-- founders column descriptions
COMMENT ON TABLE public.founders IS
  'Founders and co-founders linked to each company. Sources: CB (people.csv + people_descriptions.csv), Tracxn (People 2.1). Priority to Crunchbase. It means that if we have the company in crunchbase, we fill the whole table with crunchbase, otherwise we fill the table with tracxn. But no mixing of sources per company to avoid having 2 times the same founder';

COMMENT ON COLUMN public.founders.id IS
  'Unique identifier for the founder record. Auto-generated UUID.';

COMMENT ON COLUMN public.founders.created_at IS
  'Timestamp when the founder record was first created in the database.';

COMMENT ON COLUMN public.founders.updated_at IS
  'Timestamp of the last modification to the founder record. Automatically updated via trigger.';

COMMENT ON COLUMN public.founders.company_id IS
  'Foreign key referencing the company this founder belongs to. Cascades on delete.';

COMMENT ON COLUMN public.founders.name IS
  'Full name of the founder. Sources: CB (people.csv → first_name + last_name), Tracxn (Companies Covered 1.1 → Key People Info).';

COMMENT ON COLUMN public.founders.role IS
  'Role/title of the founder within the company (e.g. Founder, Co-founder, CEO & Founder). Sources: CB (people.csv → featured_job_title), Tracxn (Companies Covered 1.1 → Key People Info).';

COMMENT ON COLUMN public.founders.description IS
  'Description of the founder. Sources: CB (people_descriptions.csv → description), Tracxn (People 2.1 → description).';

COMMENT ON COLUMN public.founders.linkedin_url IS
  'LinkedIn profile URL of the founder. Source: CB (people.csv → linkedin_url), Tracxn (People 2.1 → profile_links).';

COMMENT ON COLUMN public.founders.source IS
  'Source of the founder data. "crunchbase" for Crunchbase, "tracxn" for Tracxn.';


-- Create the dealroom_enrichment table
CREATE TABLE IF NOT EXISTS public.dealroom_enrichment (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),

  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  storage_path TEXT, -- Path in Supabase Storage containing the raw scraped Dealroom profile
  sourcing_date DATE, -- Date when the Dealroom data was retrieved
  headcount INTEGER,
  headcount_growth_l12m NUMERIC, -- Percentage (e.g. 25.5 for 25.5%)
  web_traffic INTEGER,
  web_traffic_growth_l12m NUMERIC -- Percentage (e.g. 25.5 for 25.5%)
);

-- dealroom_enrichment column descriptions
COMMENT ON TABLE public.dealroom_enrichment IS
  'Dealroom profile enrichment data for companies. Contains scraped metrics from Dealroom, linked to the raw stored profile in Supabase Storage.';

COMMENT ON COLUMN public.dealroom_enrichment.id IS
  'Unique identifier for the enrichment record. Auto-generated UUID.';

COMMENT ON COLUMN public.dealroom_enrichment.created_at IS
  'Timestamp when the enrichment record was first created in the database.';

COMMENT ON COLUMN public.dealroom_enrichment.updated_at IS
  'Timestamp of the last modification to the enrichment record. Automatically updated via trigger.';

COMMENT ON COLUMN public.dealroom_enrichment.company_id IS
  'Foreign key referencing the company this enrichment belongs to. Cascades on delete.';

COMMENT ON COLUMN public.dealroom_enrichment.storage_path IS
  'Path in Supabase Storage pointing to the raw scraped Dealroom profile. Used to reprocess or audit enrichment data.';

COMMENT ON COLUMN public.dealroom_enrichment.sourcing_date IS
  'Date when the Dealroom profile information was retrieved/scraped. Useful to track data freshness.';

COMMENT ON COLUMN public.dealroom_enrichment.headcount IS
  'Total employee count as reported by Dealroom at sourcing_date.';

COMMENT ON COLUMN public.dealroom_enrichment.headcount_growth_l12m IS
  'Employee headcount growth over the last 12 months as reported by Dealroom, stored as percentage (e.g. 25.5 for 25.5%).';

COMMENT ON COLUMN public.dealroom_enrichment.web_traffic IS
  'Monthly web traffic (visits) as reported by Dealroom at sourcing_date.';

COMMENT ON COLUMN public.dealroom_enrichment.web_traffic_growth_l12m IS
  'Web traffic growth over the last 12 months as reported by Dealroom, stored as percentage (e.g. 25.5 for 25.5%).';

-- Create the web_scraping_enrichment table
CREATE TABLE IF NOT EXISTS public.web_scraping_enrichment (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),

  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  storage_path TEXT, -- Path in Supabase Storage containing the raw scraped website data
  sourcing_date DATE, -- Date when the website was scraped
  description TEXT,
  detailed_solution TEXT,
  key_features TEXT,
  use_cases TEXT,
  industries_served_description TEXT,
  key_clients TEXT[],
  key_partners TEXT[],
  nb_of_clients_identified TEXT
);

-- web_scraping_enrichment column descriptions
COMMENT ON TABLE public.web_scraping_enrichment IS
  'Enrichment data from scraping company websites. Contains AI-extracted structured information about the company product, clients, and market positioning.';

COMMENT ON COLUMN public.web_scraping_enrichment.id IS
  'Unique identifier for the enrichment record. Auto-generated UUID.';

COMMENT ON COLUMN public.web_scraping_enrichment.created_at IS
  'Timestamp when the enrichment record was first created in the database.';

COMMENT ON COLUMN public.web_scraping_enrichment.updated_at IS
  'Timestamp of the last modification to the enrichment record. Automatically updated via trigger.';

COMMENT ON COLUMN public.web_scraping_enrichment.company_id IS
  'Foreign key referencing the company this enrichment belongs to. Cascades on delete.';

COMMENT ON COLUMN public.web_scraping_enrichment.storage_path IS
  'Path in Supabase Storage pointing to the raw scraped website data. Used to reprocess or audit enrichment data.';

COMMENT ON COLUMN public.web_scraping_enrichment.sourcing_date IS
  'Date when the company website was scraped. Useful to track data freshness.';

COMMENT ON COLUMN public.web_scraping_enrichment.description IS
  'General description of the company and what it does, extracted from the website.';

COMMENT ON COLUMN public.web_scraping_enrichment.detailed_solution IS
  'Detailed explanation of the company product or solution offering, extracted from the website.';

COMMENT ON COLUMN public.web_scraping_enrichment.key_features IS
  'Main features or capabilities of the company product/service, extracted from the website.';

COMMENT ON COLUMN public.web_scraping_enrichment.use_cases IS
  'Target use cases or problem scenarios the company addresses, extracted from the website.';

COMMENT ON COLUMN public.web_scraping_enrichment.industries_served_description IS
  'Industries or verticals the company targets, extracted from the website.';

COMMENT ON COLUMN public.web_scraping_enrichment.key_clients IS
  'Notable clients or customers mentioned on the website.';

COMMENT ON COLUMN public.web_scraping_enrichment.key_partners IS
  'Notable partners or integrations mentioned on the website.';

COMMENT ON COLUMN public.web_scraping_enrichment.nb_of_clients_identified IS
  'Number of clients identified or claimed on the website (stored as text to accommodate ranges or qualifiers like "100+").';

-- Create the hunter_enrichment table
CREATE TABLE IF NOT EXISTS public.hunter_enrichment (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),

  founder_id UUID NOT NULL REFERENCES public.founders(id) ON DELETE CASCADE,
  storage_path TEXT, -- Path in Supabase Storage containing the raw Hunter data
  sourcing_date DATE, -- Date when the Hunter data was retrieved
  email TEXT
);

-- hunter_enrichment column descriptions
COMMENT ON TABLE public.hunter_enrichment IS
  'Hunter enrichment data for founders. Contains contact information retrieved from Hunter, linked to the raw stored response in Supabase Storage.';

COMMENT ON COLUMN public.hunter_enrichment.id IS
  'Unique identifier for the enrichment record. Auto-generated UUID.';

COMMENT ON COLUMN public.hunter_enrichment.created_at IS
  'Timestamp when the enrichment record was first created in the database.';

COMMENT ON COLUMN public.hunter_enrichment.updated_at IS
  'Timestamp of the last modification to the enrichment record. Automatically updated via trigger.';

COMMENT ON COLUMN public.hunter_enrichment.founder_id IS
  'Foreign key referencing the founder this enrichment belongs to. Cascades on delete.';

COMMENT ON COLUMN public.hunter_enrichment.storage_path IS
  'Path in Supabase Storage pointing to the raw Hunter response. Used to reprocess or audit enrichment data.';

COMMENT ON COLUMN public.hunter_enrichment.sourcing_date IS
  'Date when the Hunter data was retrieved. Useful to track data freshness.';

COMMENT ON COLUMN public.hunter_enrichment.email IS
  'Professional email address of the founder, retrieved from Hunter.';

-- Create the business_computed_values table
CREATE TABLE IF NOT EXISTS public.business_computed_values (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),

  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  calculus_date TIMESTAMPTZ NOT NULL DEFAULT now(), -- When the full calculation pipeline was last run

  -- Client/partner matching against reference lists
  global_2000_clients TEXT[], -- Global 2000 companies identified as clients of this company using fuzzy matching
  competitors_cg TEXT[], -- Capgemini competitors that are partners or clients of this company using fuzzy matching
  competitors_by TEXT[], -- Bouygues competitors that are partners or clients of this company using fuzzy matching

  -- Go-to-market targets (per fund)
  gtm_target TEXT, -- GTM target classification for Capgemini fund using generic GTM taxonomy
  gtm_target_by TEXT, -- GTM target classification for Bouygues fund using specific BY GTM taxonomy

  -- Funding round computed fields (derived from funding_rounds table)
  first_vc_round_date DATE, -- Earliest institutional VC round date cross CB and Tracxn
  first_vc_round_amount NUMERIC, -- Amount of the first institutional VC round, in millions USD cross CB and Tracxn
  last_round_lead_investors TEXT, -- Lead investor(s) of the most recent round cross CB and Tracxn
  total_number_of_funding_rounds INTEGER, -- Total number of funding rounds, max of (sum of CB vs sum of Tracxn)

  -- Business classification
  business_model TEXT, -- Business model classification for the company using business model taxonomy

  -- Sector/industry classification (per fund) - we identify the industries served from the taxonomy in order of relevance
  scope TEXT, -- "cg" for Capgemini, "by" for Bouygues, "both" for both, it depends only on the sectors and industry served
  primary_sector_served_cg TEXT, -- Primary sector for Capgemini taxonomy
  primary_industry_served_cg TEXT, -- Primary industry for Capgemini taxonomy
  primary_sector_served_by TEXT, -- Primary sector for Bouygues taxonomy
  primary_industry_served_by TEXT, -- Primary industry for Bouygues taxonomy
  all_industries_served TEXT[], -- All industries the company serves

  -- Technology classification
  tech_play TEXT, -- Primary technology play
  tech_tags TEXT[], -- Static technology tags from taxonomy
  tech_tags_dynamic TEXT[], -- Dynamically computed technology tags
  all_tech_tags TEXT[], -- Union of static + dynamic tech tags

  -- Fit scores (per fund where applicable)
  solution_fit_cg INTEGER, -- Solution fit score for Capgemini
  solution_fit_by INTEGER, -- Solution fit score for Bouygues
  business_fit_cg INTEGER, -- Business fit score for Capgemini
  business_fit_by INTEGER, -- Business fit score for Bouygues
  maturity_fit INTEGER, -- Maturity fit score (fund-agnostic)
  equity_score INTEGER, -- Equity/investment attractiveness score
  traction_score INTEGER, -- Traction/growth score
  global_fund_score INTEGER, -- Overall fund fit score

  -- Attio CRM sync
  in_attio BOOLEAN, -- Whether this company exists in Attio
  attio_stage TEXT, -- Current pipeline stage in Attio
  attio_status TEXT -- Current status in Attio
);

-- Column descriptions
COMMENT ON TABLE public.business_computed_values IS
  'ISAI business-specific computed values for each company. Contains scores, classifications, and tags generated by the calculation pipeline. Each row represents the latest computed state for a company.';

COMMENT ON COLUMN public.business_computed_values.id IS
  'Unique identifier for the computed values record. Auto-generated UUID.';

COMMENT ON COLUMN public.business_computed_values.created_at IS
  'Timestamp when the record was first created in the database.';

COMMENT ON COLUMN public.business_computed_values.updated_at IS
  'Timestamp of the last modification to the record. Automatically updated via trigger.';

COMMENT ON COLUMN public.business_computed_values.company_id IS
  'Foreign key referencing the company these computed values belong to. Cascades on delete.';

COMMENT ON COLUMN public.business_computed_values.calculus_date IS
  'Timestamp of when the full calculation pipeline was last run for this company. Critical for tracking data freshness and pipeline execution history.';

COMMENT ON COLUMN public.business_computed_values.global_2000_clients IS
  'List of Forbes Global 2000 companies identified as clients of this company. Matched against the global_2000 reference table.';

COMMENT ON COLUMN public.business_computed_values.competitors_cg IS
  'List of Capgemini competitors that are partners or clients of this company. Matched against the cap_competitors reference table.';

COMMENT ON COLUMN public.business_computed_values.competitors_by IS
  'List of Bouygues competitors that are partners or clients of this company. Matched against the by_competitors reference table.';

COMMENT ON COLUMN public.business_computed_values.gtm_target IS
  'Go-to-market target classification for the Capgemini fund perspective. Matched against the gtm_target reference table.';

COMMENT ON COLUMN public.business_computed_values.gtm_target_by IS
  'Go-to-market target classification for the Bouygues fund perspective. Matched against the gtm_target reference table.';

COMMENT ON COLUMN public.business_computed_values.first_vc_round_date IS
  'Date of the first institutional VC round, computed from the funding_rounds table (earliest round excluding angel).';

COMMENT ON COLUMN public.business_computed_values.first_vc_round_amount IS
  'Amount raised in the first institutional VC round in millions USD, computed from the funding_rounds table.';

COMMENT ON COLUMN public.business_computed_values.last_round_lead_investors IS
  'Lead investor(s) of the most recent funding round, computed from the funding_rounds table.';

COMMENT ON COLUMN public.business_computed_values.total_number_of_funding_rounds IS
  'Total number of funding rounds, computed as the max of the sum from CB vs the sum from Tracxn.';

COMMENT ON COLUMN public.business_computed_values.business_model IS
  'Business model classification for the company. Matched against the business_models reference table.';

COMMENT ON COLUMN public.business_computed_values.scope IS
  'Fund scope for this company. "cg" for Capgemini only, "by" for Bouygues only, "both" for both funds. Determined solely by the sectors and industries served.';

COMMENT ON COLUMN public.business_computed_values.primary_sector_served_cg IS
  'Primary sector the company serves, classified using the Capgemini taxonomy (cap_sectors_and_industries).';

COMMENT ON COLUMN public.business_computed_values.primary_industry_served_cg IS
  'Primary industry the company serves, classified using the Capgemini taxonomy (cap_sectors_and_industries).';

COMMENT ON COLUMN public.business_computed_values.primary_sector_served_by IS
  'Primary sector the company serves, classified for the Bouygues fund perspective.';

COMMENT ON COLUMN public.business_computed_values.primary_industry_served_by IS
  'Primary industry the company serves, classified for the Bouygues fund perspective.';

COMMENT ON COLUMN public.business_computed_values.all_industries_served IS
  'Complete list of all industries the company serves, across both fund taxonomies.';

COMMENT ON COLUMN public.business_computed_values.tech_play IS
  'Primary technology play classification. Matched against the cap_tech_play reference table.';

COMMENT ON COLUMN public.business_computed_values.tech_tags IS
  'Static technology tags assigned from the technology taxonomy.';

COMMENT ON COLUMN public.business_computed_values.tech_tags_dynamic IS
  'Dynamically computed technology tags, generated by the pipeline based on company data analysis.';

COMMENT ON COLUMN public.business_computed_values.all_tech_tags IS
  'Union of static (tech_tags) and dynamic (tech_tags_dynamic) technology tags.';

COMMENT ON COLUMN public.business_computed_values.solution_fit_cg IS
  'Solution fit score for the Capgemini fund. Integer score evaluating how well the company solution fits Capgemini needs.';

COMMENT ON COLUMN public.business_computed_values.solution_fit_by IS
  'Solution fit score for the Bouygues fund. Integer score evaluating how well the company solution fits Bouygues needs.';

COMMENT ON COLUMN public.business_computed_values.business_fit_cg IS
  'Business fit score for the Capgemini fund. Integer score evaluating business compatibility with Capgemini.';

COMMENT ON COLUMN public.business_computed_values.business_fit_by IS
  'Business fit score for the Bouygues fund. Integer score evaluating business compatibility with Bouygues.';

COMMENT ON COLUMN public.business_computed_values.maturity_fit IS
  'Maturity fit score. Fund-agnostic integer score evaluating the company maturity level for investment readiness.';

COMMENT ON COLUMN public.business_computed_values.equity_score IS
  'Equity score. Integer score evaluating the investment attractiveness from an equity perspective.';

COMMENT ON COLUMN public.business_computed_values.traction_score IS
  'Traction score. Integer score evaluating the company growth and market traction.';

COMMENT ON COLUMN public.business_computed_values.global_fund_score IS
  'Global fund fit score. Overall integer score combining all fit dimensions for fund-level decision making.';

COMMENT ON COLUMN public.business_computed_values.in_attio IS
  'Whether this company currently exists in the Attio CRM. Used for pipeline synchronization.';

COMMENT ON COLUMN public.business_computed_values.attio_stage IS
  'Current pipeline stage of the company in the Attio CRM (e.g. Sourcing, First Contact, Due Diligence).';

COMMENT ON COLUMN public.business_computed_values.attio_status IS
  'Current status of the company in the Attio CRM.';


-- Create trigger function for updated_at
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

-- Create trigger to automatically update updated_at
DROP TRIGGER IF EXISTS update_companies_updated_at ON public.companies;
CREATE TRIGGER update_companies_updated_at
  BEFORE UPDATE ON public.companies
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Create trigger for founders updated_at
DROP TRIGGER IF EXISTS update_founders_updated_at ON public.founders;
CREATE TRIGGER update_founders_updated_at
  BEFORE UPDATE ON public.founders
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Create trigger for hunter_enrichment updated_at
DROP TRIGGER IF EXISTS update_hunter_enrichment_updated_at ON public.hunter_enrichment;
CREATE TRIGGER update_hunter_enrichment_updated_at
  BEFORE UPDATE ON public.hunter_enrichment
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Create trigger for web_scraping_enrichment updated_at
DROP TRIGGER IF EXISTS update_web_scraping_enrichment_updated_at ON public.web_scraping_enrichment;
CREATE TRIGGER update_web_scraping_enrichment_updated_at
  BEFORE UPDATE ON public.web_scraping_enrichment
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Create trigger for dealroom_enrichment updated_at
DROP TRIGGER IF EXISTS update_dealroom_enrichment_updated_at ON public.dealroom_enrichment;
CREATE TRIGGER update_dealroom_enrichment_updated_at
  BEFORE UPDATE ON public.dealroom_enrichment
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Create trigger for funding_rounds updated_at
DROP TRIGGER IF EXISTS update_funding_rounds_updated_at ON public.funding_rounds;
CREATE TRIGGER update_funding_rounds_updated_at
  BEFORE UPDATE ON public.funding_rounds
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Create trigger for business_computed_values updated_at
DROP TRIGGER IF EXISTS update_business_computed_values_updated_at ON public.business_computed_values;
CREATE TRIGGER update_business_computed_values_updated_at
  BEFORE UPDATE ON public.business_computed_values
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Enable Row Level Security
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.founders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hunter_enrichment ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.web_scraping_enrichment ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dealroom_enrichment ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.funding_rounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.business_computed_values ENABLE ROW LEVEL SECURITY;

-- Create policies for authenticated users (full access)
CREATE POLICY "Authenticated users have full access"
  ON public.companies FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Authenticated users have full access"
  ON public.founders FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Authenticated users have full access"
  ON public.hunter_enrichment FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Authenticated users have full access"
  ON public.web_scraping_enrichment FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Authenticated users have full access"
  ON public.dealroom_enrichment FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Authenticated users have full access"
  ON public.funding_rounds FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Authenticated users have full access"
  ON public.business_computed_values FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);


-- Create indexes for common queries
CREATE INDEX IF NOT EXISTS idx_companies_name ON public.companies(name);
CREATE INDEX IF NOT EXISTS idx_companies_hq_country ON public.companies(hq_country);
CREATE INDEX IF NOT EXISTS idx_companies_hq_city ON public.companies(hq_city);
CREATE INDEX IF NOT EXISTS idx_companies_vc_current_stage ON public.companies(vc_current_stage);
CREATE INDEX IF NOT EXISTS idx_companies_inc_date ON public.companies(inc_date);
CREATE INDEX IF NOT EXISTS idx_companies_created_at ON public.companies(created_at);
CREATE INDEX IF NOT EXISTS idx_founders_company_id ON public.founders(company_id);
CREATE INDEX IF NOT EXISTS idx_founders_name ON public.founders(name);
CREATE INDEX IF NOT EXISTS idx_hunter_enrichment_founder_id ON public.hunter_enrichment(founder_id);
CREATE INDEX IF NOT EXISTS idx_web_scraping_enrichment_company_id ON public.web_scraping_enrichment(company_id);
CREATE INDEX IF NOT EXISTS idx_dealroom_enrichment_company_id ON public.dealroom_enrichment(company_id);
CREATE INDEX IF NOT EXISTS idx_funding_rounds_company_id ON public.funding_rounds(company_id);
CREATE INDEX IF NOT EXISTS idx_funding_rounds_date ON public.funding_rounds(date);
CREATE INDEX IF NOT EXISTS idx_funding_rounds_stage ON public.funding_rounds(stage);
CREATE INDEX IF NOT EXISTS idx_bcv_company_id ON public.business_computed_values(company_id);
CREATE INDEX IF NOT EXISTS idx_bcv_calculus_date ON public.business_computed_values(calculus_date);
CREATE INDEX IF NOT EXISTS idx_bcv_in_attio ON public.business_computed_values(in_attio);
CREATE INDEX IF NOT EXISTS idx_bcv_solution_fit_cg ON public.business_computed_values(solution_fit_cg);
CREATE INDEX IF NOT EXISTS idx_bcv_solution_fit_by ON public.business_computed_values(solution_fit_by);
CREATE INDEX IF NOT EXISTS idx_bcv_global_fund_score ON public.business_computed_values(global_fund_score);
