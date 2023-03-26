defmodule WhisperWeb.PageLive do
  use WhisperWeb, :live_view

  @impl true
  def mount(_, _, socket) do
    Nx.default_backend(EXLA.Backend)

    {:ok, whisper} = Bumblebee.load_model({:hf, "openai/whisper-tiny"})
    {:ok, featurizer} = Bumblebee.load_featurizer({:hf, "openai/whisper-tiny"})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, "openai/whisper-tiny"})

    serving =
      Bumblebee.Audio.speech_to_text(whisper, featurizer, tokenizer,
        max_new_tokens: 100,
        defn_options: [compiler: EXLA]
      )

    {:ok, assign(socket, audio: nil, recording: false, task: nil, result: nil, serving: serving)}
  end

  @impl true
  def handle_event("start", _value, socket) do
    socket = socket |> push_event("start", %{})
    {:noreply, assign(socket, recording: true)}
  end

  @impl true
  def handle_event("stop", _value, %{assigns: %{recording: recording}} = socket) do
    socket =
      if recording do
        socket |> push_event("stop", %{})
      else
        socket
      end

    {:noreply, assign(socket, recording: false)}
  end

  @impl true
  def handle_event(
        "audio_done",
        %{"data" => base64_audio},
        %{assigns: %{serving: serving}} = socket
      ) do
    base64_data = String.split(base64_audio, ",", parts: 2) |> List.last()
    decoded_audio = Base.decode64!(base64_data)
    "talk.wav" |> File.write!(decoded_audio)

    task =
      Task.async(fn ->
        Process.sleep(300)
        Nx.Serving.run(serving, {:file, "talk.wav"})
      end)

    {:noreply, assign(socket, recording: false, task: task, result: nil)}
  end

  @impl true
  def handle_info({ref, x}, socket) when socket.assigns.task.ref == ref do
    result =
      x.results
      |> Enum.reduce("", fn r, acc -> acc <> "#{r.text}" end)

    {:noreply, assign(socket, task: nil, result: result)}
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen">
      <div :if={@result} class="pt-4">
        <div class="flex w-full justify-center items-center text-blue-400 font-bold">
          <%= @result %>
        </div>
      </div>
      <div class="flex h-screen w-full justify-center items-center">
        <div id="mic-element" class="flex h-20 w-20 rounded-full bg-gray-700 p-2" phx-hook="Demo">
          <div
            :if={@task}
            class="h-full w-full bg-white rounded-full ring-2 ring-white animate-spin border-4 border-solid border-blue-500 border-t-transparent"
          >
          </div>
          <button
            :if={!@task && !@recording}
            class="h-full w-full bg-red-500 rounded-full ring-2 ring-white"
            type="button"
            phx-click="start"
            class="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded"
          >
          </button>
          <button
            :if={!@task && @recording}
            class="h-full w-full bg-red-500 rounded-full ring-2 ring-white animate-pulse"
            type="button"
            phx-click="stop"
            class="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded"
          >
          </button>
        </div>
      </div>
    </div>
    """
  end
end
