IO.puts "=== Current Database Indexes ==="
result = EventasaurusApp.Repo.query!("""
  SELECT indexname, tablename, indexdef 
  FROM pg_indexes 
  WHERE schemaname = 'public' 
    AND tablename IN ('events', 'event_users', 'event_participants', 'venues') 
  ORDER BY tablename, indexname;
""")

result.rows
|> Enum.each(fn [name, table, def] -> 
  IO.puts "#{table}.#{name}: #{def}" 
end)