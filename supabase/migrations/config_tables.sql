-- =============================================
-- Configuration / constant tables
-- =============================================

-- Global 2000 reference list (Forbes Global 2000 companies)
CREATE TABLE IF NOT EXISTS public.global_2000 (
  name TEXT PRIMARY KEY,
  country TEXT
);

COMMENT ON TABLE public.global_2000 IS
  'Reference list of Forbes Global 2000 companies. Used as a pipeline configuration table to match and validate key clients/partners.';

COMMENT ON COLUMN public.global_2000.name IS
  'Company name, used as primary key.';

COMMENT ON COLUMN public.global_2000.country IS
  'Country where the Global 2000 company is headquartered.';

ALTER TABLE public.global_2000 ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users have full access"
  ON public.global_2000 FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- CAP affiliates reference list
CREATE TABLE IF NOT EXISTS public.cap_affiliates (
  name TEXT PRIMARY KEY,
  description TEXT
);

COMMENT ON TABLE public.cap_affiliates IS
  'Reference list of Capgemini affiliate companies. Used as a pipeline configuration table for affiliate matching.';

COMMENT ON COLUMN public.cap_affiliates.name IS
  'Affiliate company name, used as primary key.';

COMMENT ON COLUMN public.cap_affiliates.description IS
  'Description of the Capgemini affiliate company.';

ALTER TABLE public.cap_affiliates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users have full access"
  ON public.cap_affiliates FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- Capgemini competitors reference list
CREATE TABLE IF NOT EXISTS public.cap_competitors (
  name TEXT PRIMARY KEY,
  category TEXT
);

COMMENT ON TABLE public.cap_competitors IS
  'Reference list of Capgemini competitor companies. Used as a pipeline configuration table for competitor matching.';

COMMENT ON COLUMN public.cap_competitors.name IS
  'Competitor company name, used as primary key.';

COMMENT ON COLUMN public.cap_competitors.category IS
  'Category or type of competitor.';

ALTER TABLE public.cap_competitors ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users have full access"
  ON public.cap_competitors FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- Capgemini software partners reference list
CREATE TABLE IF NOT EXISTS public.cap_sw_partners (
  name TEXT PRIMARY KEY
);

COMMENT ON TABLE public.cap_sw_partners IS
  'Reference list of Capgemini software partners. Used as a pipeline configuration table for software partner matching.';

COMMENT ON COLUMN public.cap_sw_partners.name IS
  'Software partner company name, used as primary key.';

ALTER TABLE public.cap_sw_partners ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users have full access"
  ON public.cap_sw_partners FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- Bouygues affiliates reference list
CREATE TABLE IF NOT EXISTS public.by_affiliates (
  name TEXT PRIMARY KEY,
  business_unit TEXT
);

COMMENT ON TABLE public.by_affiliates IS
  'Reference list of Bouygues affiliate companies. Used as a pipeline configuration table for affiliate matching.';

COMMENT ON COLUMN public.by_affiliates.name IS
  'Affiliate company name, used as primary key.';

COMMENT ON COLUMN public.by_affiliates.business_unit IS
  'Business unit within Bouygues the affiliate belongs to.';

ALTER TABLE public.by_affiliates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users have full access"
  ON public.by_affiliates FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- Bouygues competitors reference list
CREATE TABLE IF NOT EXISTS public.by_competitors (
  name TEXT PRIMARY KEY
);

COMMENT ON TABLE public.by_competitors IS
  'Reference list of Bouygues competitor companies. Used as a pipeline configuration table for competitor matching.';

COMMENT ON COLUMN public.by_competitors.name IS
  'Competitor company name, used as primary key.';

ALTER TABLE public.by_competitors ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users have full access"
  ON public.by_competitors FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- Bouygues platforms reference list
CREATE TABLE IF NOT EXISTS public.by_platforms (
  name TEXT PRIMARY KEY,
  description TEXT
);

COMMENT ON TABLE public.by_platforms IS
  'Reference list of key platforms used by Bouygues for construction. Used as a pipeline configuration table for platform matching.';

COMMENT ON COLUMN public.by_platforms.name IS
  'Platform company name, used as primary key.';

COMMENT ON COLUMN public.by_platforms.description IS
  'Description of the platform.';

ALTER TABLE public.by_platforms ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users have full access"
  ON public.by_platforms FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- Capgemini sectors and industries taxonomy
CREATE TABLE IF NOT EXISTS public.industries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  scope TEXT,
  sector TEXT,
  industry TEXT,
  description TEXT,
  UNIQUE (scope, sector, industry)
);

COMMENT ON TABLE public.industries IS
  'Taxonomy of industries used by Capgemini. Hierarchical classification with sector as top level and two levels of industry labels. Used as a pipeline configuration table to classify companies.';

COMMENT ON COLUMN public.industries.id IS
  'Unique identifier. Auto-generated UUID.';

COMMENT ON COLUMN public.industries.scope IS
  'Fund scope for this sector/industry. "cg" for Capgemini only, "by" for Bouygues only.';

COMMENT ON COLUMN public.industries.sector IS
  'Top-level sector name in the Capgemini taxonomy.';

COMMENT ON COLUMN public.industries.industry IS
  'First-level industry label within the sector.';

COMMENT ON COLUMN public.industries.description IS
  'Description of the sector/industry.';

ALTER TABLE public.industries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users have full access"
  ON public.industries FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- Business models reference list
CREATE TABLE IF NOT EXISTS public.business_models (
  name TEXT PRIMARY KEY,
  description TEXT
);

COMMENT ON TABLE public.business_models IS
  'Reference list of business model types. Used as a pipeline configuration table to classify companies by their business model.';

COMMENT ON COLUMN public.business_models.name IS
  'Business model name, used as primary key.';

COMMENT ON COLUMN public.business_models.description IS
  'Description of the business model.';

ALTER TABLE public.business_models ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users have full access"
  ON public.business_models FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- Go-to-market target reference list
CREATE TABLE IF NOT EXISTS public.gtm_target (
  scope TEXT,
  target TEXT PRIMARY KEY,
  description TEXT
);

COMMENT ON TABLE public.gtm_target IS
  'Reference list of go-to-market target segments. Used as a pipeline configuration table to classify companies by their GTM target (e.g. B2B, B2C, B2B2C).';

COMMENT ON COLUMN public.gtm_target.scope IS
  'Fund scope for this GTM target. "cg" for Capgemini only, "by" for Bouygues only. "both" for both funds.';

COMMENT ON COLUMN public.gtm_target.target IS
  'GTM target name, used as primary key.';

COMMENT ON COLUMN public.gtm_target.description IS
  'Description of the go-to-market target segment.';

ALTER TABLE public.gtm_target ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users have full access"
  ON public.gtm_target FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- Schools reference list
CREATE TABLE IF NOT EXISTS public.schools (
  name TEXT PRIMARY KEY,
  country TEXT,
  tier INTEGER
);

COMMENT ON TABLE public.schools IS
  'Reference list of schools and universities. Used as a pipeline configuration table to evaluate founder education quality and tier ranking.';

COMMENT ON COLUMN public.schools.name IS
  'School or university name, used as primary key.';

COMMENT ON COLUMN public.schools.country IS
  'Country where the school is located.';

COMMENT ON COLUMN public.schools.tier IS
  'Quality tier ranking of the school (e.g. 1 = top tier).';

ALTER TABLE public.schools ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users have full access"
  ON public.schools FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- VC funds reference list
CREATE TABLE IF NOT EXISTS public.vc_funds (
  name TEXT PRIMARY KEY,
  country TEXT,
  tier INTEGER
);

COMMENT ON TABLE public.vc_funds IS
  'Reference list of venture capital funds. Used as a pipeline configuration table to evaluate investor quality and tier ranking.';

COMMENT ON COLUMN public.vc_funds.name IS
  'VC fund name, used as primary key.';

COMMENT ON COLUMN public.vc_funds.country IS
  'Country where the VC fund is headquartered.';

COMMENT ON COLUMN public.vc_funds.tier IS
  'Quality tier ranking of the VC fund (e.g. 1 = top tier).';

ALTER TABLE public.vc_funds ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users have full access"
  ON public.vc_funds FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);
