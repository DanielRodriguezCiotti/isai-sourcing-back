-- Migration: Create Tracxn tables for companies, funding rounds, and founders
-- Created: 2026-02-09

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- Table: traxcn_companies
-- ============================================================
CREATE TABLE IF NOT EXISTS traxcn_companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_name TEXT NOT NULL,
    domain_name TEXT UNIQUE NOT NULL,
    overview TEXT,
    founded_year INTEGER,
    country TEXT,
    state TEXT,
    city TEXT,
    description TEXT,
    sector TEXT[],
    business_models TEXT[],
    team_background TEXT,
    waves TEXT[],
    trending_themes TEXT[],
    special_flags TEXT[],
    company_stage TEXT,
    all_associated_legal_entities TEXT,
    is_funded BOOLEAN,
    total_funding_in_usd NUMERIC(15, 2),
    latest_funded_amount_in_usd NUMERIC(15, 2),
    latest_funded_date DATE,
    latest_valuation_in_usd TEXT,
    institutional_investors TEXT[],
    angel_investors TEXT[],
    annual_revenue_in_usd TEXT,
    annual_net_profit_in_usd TEXT,
    annual_ebitda_in_usd TEXT,
    key_people_info TEXT,
    key_people_email_ids TEXT[],
    links_to_key_people_profiles TEXT[],
    total_employee_count TEXT,
    acquisition_list TEXT[],
    is_acquired BOOLEAN,
    is_ipo BOOLEAN,
    editors_rating NUMERIC(3, 1),
    editors_rated_date DATE,
    tracxn_score NUMERIC(10, 8),
    company_emails TEXT[],
    company_phone_numbers TEXT,
    website TEXT,
    website_status TEXT,
    website_status_last_updated DATE,
    linkedin TEXT,
    twitter TEXT,
    facebook TEXT,
    blog_url TEXT,
    tracxn_url TEXT,
    date_added DATE,
    is_deadpooled BOOLEAN,
    part_of TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);


-- ============================================================
-- Table: traxcn_funding_rounds
-- ============================================================
CREATE TABLE IF NOT EXISTS traxcn_funding_rounds (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    round_date DATE,
    company_name TEXT NOT NULL,
    domain_name TEXT NOT NULL,
    round_name TEXT,
    round_amount_in_usd NUMERIC(15, 2),
    round_pre_money_valuation_in_usd NUMERIC(15, 2),
    round_post_money_valuation_in_usd NUMERIC(15, 2),
    round_trailing_12m_revenue_in_usd NUMERIC(15, 2),
    institutional_investors TEXT[],
    angel_investors TEXT[],
    lead_investor TEXT[],
    facilitators TEXT[],
    total_funding_in_usd NUMERIC(15, 2),
    round_revenue_multiple NUMERIC(10, 2),
    overview TEXT,
    founded_year INTEGER,
    country TEXT,
    state TEXT,
    city TEXT,
    practice_areas TEXT[],
    feed_name TEXT[],
    business_models TEXT[],
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT fk_company FOREIGN KEY (domain_name)
        REFERENCES traxcn_companies(domain_name)
        ON DELETE CASCADE,
    CONSTRAINT uq_traxcn_funding_identity UNIQUE (round_date, domain_name, round_name)
);


-- ============================================================
-- Table: traxcn_founders 
-- unicity of (founder_name, title, domain_name)
-- ============================================================
CREATE TABLE IF NOT EXISTS traxcn_founders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    founder_name TEXT NOT NULL,
    title TEXT,
    company_name TEXT NOT NULL,
    domain_name TEXT NOT NULL,
    people_location TEXT,
    profile_links TEXT,
    emails TEXT[],
    description TEXT,
    photo_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT fk_founder_company FOREIGN KEY (domain_name)
        REFERENCES traxcn_companies(domain_name)
        ON DELETE CASCADE,
    CONSTRAINT uq_traxcn_founder_identity UNIQUE (founder_name, title, domain_name)
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
CREATE TRIGGER update_traxcn_companies_updated_at
    BEFORE UPDATE ON traxcn_companies
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_traxcn_funding_rounds_updated_at
    BEFORE UPDATE ON traxcn_funding_rounds
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_traxcn_founders_updated_at
    BEFORE UPDATE ON traxcn_founders
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- Add comments to tables
-- ============================================================
COMMENT ON TABLE traxcn_companies IS 'Stores company information from Tracxn including funding, team, and business details. Uses TEXT[] arrays for efficient storage of string lists (investors, emails, etc.)';
COMMENT ON TABLE traxcn_funding_rounds IS 'Stores funding round details for companies including investors and valuations. Uses TEXT[] arrays for investor lists and categories.';
COMMENT ON TABLE traxcn_founders IS 'Stores founder and key people information linked to companies. Uses TEXT[] for email lists.';

-- ============================================================
-- Enable Row Level Security (RLS) - Recommended for Supabase
-- ============================================================
ALTER TABLE traxcn_companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE traxcn_funding_rounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE traxcn_founders ENABLE ROW LEVEL SECURITY;

-- Create policies for authenticated users (adjust as needed)
CREATE POLICY "Enable read access for all users" ON traxcn_companies
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON traxcn_funding_rounds
    FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON traxcn_founders
    FOR SELECT USING (true);

-- For write access, create more restrictive policies as needed
-- Example: Only allow authenticated users to insert/update
-- CREATE POLICY "Enable insert for authenticated users" ON traxcn_companies
--     FOR INSERT WITH CHECK (auth.role() = 'authenticated');
