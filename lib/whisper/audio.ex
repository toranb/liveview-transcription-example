defmodule Whisper.Audio do
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
end
