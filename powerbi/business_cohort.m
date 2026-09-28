let
    // Set the server/database through Power BI's PostgreSQL source dialog.
    Source = PostgreSQL.Database("localhost:5432", "survival_abc", [CreateNavigationProperties=false]),
    Analytics = Source{[Schema="analytics", Item="business_cohort"]}[Data]
in
    Analytics
