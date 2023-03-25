defmodule Whisper.Repo do
  use Ecto.Repo,
    otp_app: :whisper,
    adapter: Ecto.Adapters.Postgres
end
