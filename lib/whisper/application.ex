defmodule Whisper.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Nx.default_backend(EXLA.Backend)

    {:ok, whisper} = Bumblebee.load_model({:hf, "openai/whisper-tiny"})
    {:ok, featurizer} = Bumblebee.load_featurizer({:hf, "openai/whisper-tiny"})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, "openai/whisper-tiny"})

    serving =
      Bumblebee.Audio.speech_to_text(whisper, featurizer, tokenizer,
        max_new_tokens: 100,
        defn_options: [compiler: EXLA]
      )

    children = [
      {Task.Supervisor, name: Whisper.TaskSupervisor},
      # Start the Telemetry supervisor
      WhisperWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Whisper.PubSub},
      # Start Finch
      {Finch, name: Whisper.Finch},
      # Start Nx Serving
      {Nx.Serving, name: WhisperServing, serving: serving},
      # Start the Endpoint (http/https)
      WhisperWeb.Endpoint
      # Start a worker by calling: Whisper.Worker.start_link(arg)
      # {Whisper.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Whisper.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WhisperWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
