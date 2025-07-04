defmodule Eventasaurus.Mailer do
  @moduledoc """
  Swoosh mailer for sending emails via Resend.
  """
  use Swoosh.Mailer, otp_app: :eventasaurus
end
