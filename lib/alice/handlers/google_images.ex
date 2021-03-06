defmodule Alice.Handlers.GoogleImages do
  use Alice.Router
  import Application, only: [get_env: 2]

  @url "https://www.googleapis.com/customsearch/v1"

  route ~r/(image|img)\s+me (?<term>.+)/i, :fetch
  command ~r/(image|img)\s+me (?<term>.+)/i, :fetch

  @doc "`img me ____` - gets a random image from Google Images"
  def fetch(conn) do
    conn
    |> extract_term
    |> get_images
    |> select_image
    |> test_image
    |> reply(conn)
  end

  def extract_term(conn) do
    conn.message.captures
    |> Enum.reverse
    |> hd
  end

  defp http do
    case Mix.env do
      :test -> FakeHTTPoison
      _else -> HTTPoison
    end
  end

  def get_images(term) do
    case http.get(@url, [], params: query_params(term)) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, body}
      {:ok, response} ->
        reason = parse_error(response)
        Logger.warn("Google Images: Something went wrong, #{reason}")
        {:error, reason}
      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.warn("Couldn't get image from Google: #{reason}")
        {:error, reason}
    end
  end

  def query_params(term) do
    [ q: term,
      v: "1.0",
      searchType: "image",
      cx: get_env(:alice_google_images, :cse_id),
      key: get_env(:alice_google_images, :cse_token),
      safe: safe_value,
      fields: "items(link)",
      rsz: 8 ]
  end

  defp safe_value, do: safe_value(get_env(:alice_google_images, :safe_search_level))
  defp safe_value(level) when level in [:high, :medium, :off], do: level
  defp safe_value(_), do: :high

  defp parse_error(response) do
    response.body
    |> Poison.decode!
    |> get_in(["error", "errors"])
    |> case do
      [error|_] -> Map.get(error, "reason", "unknown")
      _         -> "unknown"
    end
  end

  defp select_image({:error, reason}), do: "Error: #{reason}"
  defp select_image({:ok, body}) do
    body
    |> Poison.decode!
    |> Map.get("items", [%{}])
    |> Enum.random
    |> Map.get("link")
  end

  defp test_image(nil), do: "No images found"
  defp test_image(image) do
    case http.get(image) do
      {:ok, %HTTPoison.Response{status_code: 200}} -> image
      _ -> bad_image_response
    end
  end

  defp bad_image_response do
    [
      "I found an image but I'm not feeling it",
      "Nah",
      "You wouldn't like the results of that search anyway",
      "You can do better than that"
    ] |> Enum.random
  end
end
