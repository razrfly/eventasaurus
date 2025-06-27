defmodule EventasaurusWeb.ThemeController do
  use EventasaurusWeb, :controller

  def show(conn, %{"theme_name" => theme_name}) do
    # Only allow .css files and prevent directory traversal
    if String.ends_with?(theme_name, ".css") and not String.contains?(theme_name, "..") do
      theme_path = Path.join([File.cwd!(), "assets/css/themes", theme_name])

      if File.exists?(theme_path) do
        css_content = File.read!(theme_path)

        conn
        |> put_resp_content_type("text/css")
        |> put_resp_header("cache-control", "no-cache, no-store, must-revalidate")
        |> put_resp_header("pragma", "no-cache")
        |> put_resp_header("expires", "0")
        |> send_resp(200, css_content)
      else
        send_resp(conn, 404, "Theme not found")
      end
    else
      send_resp(conn, 400, "Invalid theme name")
    end
  end
end
