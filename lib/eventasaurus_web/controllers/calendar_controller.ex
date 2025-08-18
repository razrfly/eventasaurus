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
            ics_content = CalendarExport.generate_ics(event, venue, event_url)
            
            conn
            |> put_resp_content_type("text/calendar")
            |> put_resp_header("content-disposition", "attachment; filename=\"#{event.slug}.ics\"")
            |> send_resp(200, ics_content)
          
          "google" ->
            # Redirect to Google Calendar URL
            google_url = CalendarExport.google_calendar_url(event, venue, event_url)
            redirect(conn, external: google_url)
          
          "outlook" ->
            # Redirect to Outlook Calendar URL
            outlook_url = CalendarExport.outlook_calendar_url(event, venue, event_url)
            redirect(conn, external: outlook_url)
          
          _ ->
            conn
            |> put_status(:bad_request)
            |> text("Invalid calendar format")
        end
    end
  end
end