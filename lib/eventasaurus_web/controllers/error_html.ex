defmodule EventasaurusWeb.ErrorHTML do
  use EventasaurusWeb, :html

  # Custom error pages with dinosaur theme
  # Templates located in:
  #   * lib/eventasaurus_web/controllers/error_html/404.html.heex
  #   * lib/eventasaurus_web/controllers/error_html/500.html.heex
  embed_templates "error_html/*"

  # Fallback for any error templates we haven't customized
  # For example, "403.html" becomes "Forbidden"
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
