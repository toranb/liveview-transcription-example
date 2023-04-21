defmodule WhisperWeb.PageLive do
  use WhisperWeb, :live_view

  @impl true
  def mount(_, _, socket) do
    socket =
      socket
      |> assign(audio: nil, recording: false, task: nil)
      |> allow_upload(:audio, accept: :any, progress: &handle_progress/3, auto_upload: true)
      |> stream(:segments, [], dom_id: &"ss-#{&1.ss}")

    {:ok, socket}
  end

  @impl true
  def handle_event("start", _value, socket) do
    socket = socket |> push_event("start", %{})
    {:noreply, assign(socket, recording: true)}
  end

  @impl true
  def handle_event("stop", _value, %{assigns: %{recording: recording}} = socket) do
    socket = if recording, do: socket |> push_event("stop", %{}), else: socket
    {:noreply, assign(socket, recording: false)}
  end

  @impl true
  def handle_event("noop", %{}, socket) do
    # We need phx-change and phx-submit on the form for live uploads
    {:noreply, socket}
  end

  @impl true
  def handle_info({ref, results}, socket) when socket.assigns.task.ref == ref do
    socket = socket |> assign(task: nil)

    socket =
      results
      |> Enum.reduce(socket, fn {_duration, ss, text}, socket ->
        socket |> stream_insert(:segments, %{ss: ss, text: text})
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_info(_, socket) do
    {:noreply, socket}
  end

  def handle_progress(:audio, entry, socket) when entry.done? do
    path =
      consume_uploaded_entry(socket, entry, fn upload ->
        dest = Path.join(["priv", "static", "uploads", Path.basename(upload.path)])
        File.cp!(upload.path, dest)
        {:ok, dest}
      end)

    {:ok, %{duration: duration}} = Mp3Duration.parse(path)

    task =
      speech_to_text(duration, path, 20, fn ss, text ->
        {duration, ss, text}
      end)

    {:noreply, assign(socket, task: task)}
  end

  def handle_progress(_name, _entry, socket), do: {:noreply, socket}

  def speech_to_text(duration, path, chunk_time, func) do
    Task.async(fn ->
      format = get_format()

      0..duration//chunk_time
      |> Task.async_stream(
        fn ss ->
          args = ~w(-ac 1 -ar 16k -f #{format} -ss #{ss} -t #{chunk_time} -v quiet -)
          {data, 0} = System.cmd("ffmpeg", ["-i", path] ++ args)
          {ss, Nx.Serving.batched_run(WhisperServing, Nx.from_binary(data, :f32))}
        end,
        max_concurrency: 4,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, {ss, %{results: [%{text: text}]}}} ->
        func.(ss, text)
      end)
    end)
  end

  def get_format() do
    case System.endianness() do
      :little -> "f32le"
      :big -> "f32be"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen">
      <div id="transcript" phx-update="stream" class="pt-4">
        <div
          :for={{id, segment} <- @streams.segments}
          id={id}
          class="flex w-full justify-center items-center text-blue-400 font-bold"
        >
          <%= segment.text %>
        </div>
      </div>
      <div class="flex h-screen w-full justify-center items-center">
        <form phx-change="noop" phx-submit="noop" class="hidden">
          <.live_file_input upload={@uploads.audio} />
        </form>
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
