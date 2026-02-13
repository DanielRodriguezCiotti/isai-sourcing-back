CREATE OR REPLACE VIEW public.company_overview AS
SELECT
  -- Fund scope
  bcv.scope AS fund_prime_scope,

  -- Company basics
  c.logo,
  c.name,
  c.domain AS website,
  c.hq_country,
  c.hq_city,
  c.inc_date,

  -- Web scraping (latest entry per domain)
  wse.description,
  wse.detailed_solution,
  wse.use_cases,
  wse.key_clients AS clients_served,
  wse.nb_of_clients_identified AS number_of_clients_identified,

  -- Business computed - clients/partners
  bcv.global_2000_clients,
  bcv.platforms_cg AS cg_key_platforms,
  bcv.platforms_by AS by_key_platforms,
  bcv.competitors_cg,
  bcv.competitors_by,

  -- GTM
  bcv.gtm_target AS gtm_target_cg,
  bcv.gtm_target_by,

  -- Funding
  bvc.vc_current_stage,
  bcv.first_vc_round_date,
  bcv.first_vc_round_amount,
  c.total_amount_raised,
  bcv.last_vc_round_amount AS last_funding_amount,
  bcv.last_vc_round_date AS last_funding_date,
  bcv.all_investors,
  bcv.last_round_lead_investors,
  bcv.total_number_of_funding_rounds AS total_nber_of_rounds,

  -- Business
  bcv.business_model,
  bcv.founders_background,
  bcv.serial_entrepreneur,

  -- Sectors/industries
  bcv.primary_sector_served_cg,
  bcv.primary_industry_served_cg,
  bcv.primary_sector_served_by,
  bcv.primary_industry_served_by,
  bcv.all_industries_served_sorted AS all_industries_served,
  bcv.business_mapping,
  bcv.all_tech_tags AS tech_tags_auto,

  -- Scores
  bcv.solution_fit_cg,
  bcv.solution_fit_by,
  bcv.business_fit_cg,
  bcv.business_fit_by,
  bcv.maturity_fit AS maturity_fit_score,
  bcv.equity_score,
  bcv.traction_score,
  bcv.global_fund_score AS global_fund_fit_score,

  -- Attio
  bcv.in_attio AS present_in_attio,
  bcv.attio_stage AS last_stage_in_attio,
  bcv.attio_status AS last_status_in_attio

FROM public.companies c
LEFT JOIN public.business_computed_values bcv ON bcv.domain = c.domain
LEFT JOIN LATERAL (
  SELECT *
  FROM public.web_scraping_enrichment w
  WHERE w.domain = c.domain
  ORDER BY w.sourcing_date DESC NULLS LAST
  LIMIT 1
) wse ON true;