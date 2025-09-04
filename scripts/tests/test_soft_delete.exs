
import Ecto.Query
alias EventasaurusApp.{Repo, Events.Event, Events.Ticket, Events.Order, Events.Poll, Events.PollOption, Events.PollVote, Events.EventParticipant, Events.EventUser}

IO.puts "Testing soft delete functionality..."
repo_functions = Repo.__info__(:functions) |> Enum.filter(fn {name, _} -> String.contains?(to_string(name), "soft") end)
IO.puts "Available soft delete functions in Repo: #{inspect(repo_functions)}"

IO.puts "Event schema has soft delete: #{function_exported?(Event, :__soft_delete_schema__, 0)}"
IO.puts "Ticket schema has soft delete: #{function_exported?(Ticket, :__soft_delete_schema__, 0)}"
IO.puts "Order schema has soft delete: #{function_exported?(Order, :__soft_delete_schema__, 0)}"
IO.puts "Poll schema has soft delete: #{function_exported?(Poll, :__soft_delete_schema__, 0)}"
IO.puts "PollOption schema has soft delete: #{function_exported?(PollOption, :__soft_delete_schema__, 0)}"
IO.puts "PollVote schema has soft delete: #{function_exported?(PollVote, :__soft_delete_schema__, 0)}"
IO.puts "EventParticipant schema has soft delete: #{function_exported?(EventParticipant, :__soft_delete_schema__, 0)}"
IO.puts "EventUser schema has soft delete: #{function_exported?(EventUser, :__soft_delete_schema__, 0)}"

System.halt(0)

