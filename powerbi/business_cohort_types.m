= Table.TransformColumnTypes(
    business_cohort,
    {
        {"cnpj_basic", type text},
        {"municipality", type text},
        {"municipality_code_rfb", type text},
        {"state_code", type text},
        {"opened_at", type date},
        {"registration_status_code", type text},
        {"registration_status_date", type date},
        {"is_closed", type logical},
        {"closed_at", type date},
        {"primary_cnae_code", type text},
        {"primary_cnae_description", type text},
        {"cnae_division", type text},
        {"company_size", type text},
        {"capital_social", Currency.Type},
        {"is_simples", type logical},
        {"is_mei", type logical},
        {"simples_option_date", type date},
        {"simples_exclusion_date", type date},
        {"mei_option_date", type date},
        {"mei_exclusion_date", type date},
        {"snapshot_date", type date}
    }
)
