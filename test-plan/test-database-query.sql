-- Test query to verify database connection
SELECT 
    'Database Connection Test' as test_name,
    current_database() as current_database,
    current_user as current_user,
    version() as postgres_version,
    NOW() as current_timestamp;
