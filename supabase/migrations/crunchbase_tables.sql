-- Migration: Create Crunchbase tables for companies, funding rounds, and founders
-- Created: 2026-02-10

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- Table: crunchbase_companies
-- ============================================================
CREATE TABLE IF NOT EXISTS crunchbase_companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    crunchbase_id TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    legal_name TEXT,
    domain TEXT NOT NULL UNIQUE,
    homepage_url TEXT,
    country_code TEXT,
    state_code TEXT,
    region TEXT,
    city TEXT,
    address TEXT,
    postal_code TEXT,
    status TEXT,
    short_description TEXT,
    category_list TEXT[],
    category_groups_list TEXT[],
    num_funding_rounds INTEGER,
    total_funding_usd NUMERIC(15, 2),
    founded_on DATE,
    last_funding_on DATE,
    email TEXT,
    phone TEXT,
    facebook_url TEXT,
    linkedin_url TEXT,
    twitter_url TEXT,
    logo_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);


-- ============================================================
-- Table: crunchbase_funding_rounds
-- ============================================================
CREATE TABLE IF NOT EXISTS crunchbase_funding_rounds (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    crunchbase_company_uuid TEXT NOT NULL,
    name TEXT,
    investment_type TEXT,
    announced_on DATE,
    raised_amount_usd NUMERIC(15, 2),
    post_money_valuation_usd NUMERIC(15, 2),
    investor_count INTEGER,
    lead_investors TEXT[],
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT fk_funding_round_company FOREIGN KEY (crunchbase_company_uuid)
        REFERENCES crunchbase_companies(crunchbase_id)
        ON DELETE CASCADE,
    CONSTRAINT uq_crunchbase_funding_identity UNIQUE (announced_on, crunchbase_company_uuid, investment_type)
);


-- ============================================================
-- Table: crunchbase_founders
-- ============================================================
CREATE TABLE IF NOT EXISTS crunchbase_founders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    crunchbase_company_uuid TEXT NOT NULL,
    name TEXT NOT NULL,
    first_name TEXT,
    last_name TEXT,
    gender TEXT,
    job_title TEXT,
    facebook_url TEXT,
    linkedin_url TEXT,
    twitter_url TEXT,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT fk_founder_company FOREIGN KEY (crunchbase_company_uuid)
        REFERENCES crunchbase_companies(crunchbase_id)
        ON DELETE CASCADE,
    CONSTRAINT uq_crunchbase_founder_identity UNIQUE (crunchbase_company_uuid, name, job_title)
);

-- ============================================================
-- Create updated_at trigger function
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply updated_at triggers to all tables
CREATE TRIGGER update_crunchbase_companies_updated_at
    BEFORE UPDATE ON crunchbase_companies
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_crunchbase_funding_rounds_updated_at
    BEFORE UPDATE ON crunchbase_funding_rounds
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_crunchbase_founders_updated_at
    BEFORE UPDATE ON crunchbase_founders
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- Add comments to tables
-- ============================================================
COMMENT ON TABLE crunchbase_companies IS 'Stores company information from Crunchbase including funding, location, and contact details. Uses TEXT[] arrays for category lists.';
COMMENT ON TABLE crunchbase_funding_rounds IS 'Stores funding round details for companies including valuation and investor data. Uses TEXT[] for lead investor lists.';
COMMENT ON TABLE crunchbase_founders IS 'Stores founder and key people information linked to companies via crunchbase_company_uuid.';

-- ============================================================
-- Enable Row Level Security (RLS) - Recommended for Supabase
-- ============================================================
ALTER TABLE crunchbase_companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE crunchbase_funding_rounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE crunchbase_founders ENABLE ROW LEVEL SECURITY;

-- Create policies for authenticated users (adjust as needed)
CREATE POLICY "Enable read access for all users" ON crunchbase_companies
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON crunchbase_funding_rounds
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON crunchbase_founders
    FOR SELECT USING (true);

-- For write access, create more restrictive policies as needed
-- Example: Only allow authenticated users to insert/update
-- CREATE POLICY "Enable insert for authenticated users" ON crunchbase_companies
--     FOR INSERT WITH CHECK (auth.role() = 'authenticated');
