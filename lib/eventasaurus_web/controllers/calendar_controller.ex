defmodule EventasaurusWeb.CalendarController do
  use EventasaurusWeb, :controller
  
  alias EventasaurusApp.Events
  alias EventasaurusApp.Venues
  alias EventasaurusWeb.CalendarExport
  
  def export(conn, %{"slug" => slug, "format" => format}) do
    case Events.get_event_by_slug(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> text("Event not found")
      
      event ->
        venue = if event.venue_id, do: Venues.get_venue(event.venue_id), else: nil
        event_url = url(conn, ~p"/#{event.slug}")
        
        case format do
          "ics" ->
            # Generate ICS file content
            case CalendarExport.generate_ics(event, venue, event_url) do
              {:error, :missing_start_at} ->
                conn
                |> put_status(:bad_request)
                |> text("Cannot export event to calendar: Event date/time is not set")
              
              ics_content when is_binary(ics_content) ->
                conn
                |> put_resp_content_type("text/calendar")
                |> put_resp_header("content-disposition", "attachment; filename=\"#{event.slug}.ics\"")
                |> send_resp(200, ics_content)
            end
          
          "google" ->
            # Redirect to Google Calendar URL
            case CalendarExport.google_calendar_url(event, venue, event_url) do
              {:error, :missing_start_at} ->
                conn
                |> put_status(:bad_request)
                |> text("Cannot export event to calendar: Event date/time is not set")
              
              google_url when is_binary(google_url) ->
                redirect(conn, external: google_url)
            end
          
          "outlook" ->
            # Redirect to Outlook Calendar URL
            case CalendarExport.outlook_calendar_url(event, venue, event_url) do
              {:error, :missing_start_at} ->
                conn
                |> put_status(:bad_request)
                |> text("Cannot export event to calendar: Event date/time is not set")
              
              outlook_url when is_binary(outlook_url) ->
                redirect(conn, external: outlook_url)
            end
          
          _ ->
            conn
            |> put_status(:bad_request)
            |> text("Invalid calendar format")
        end
    end
  end
end