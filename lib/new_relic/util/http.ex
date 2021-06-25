defmodule NewRelic.Util.HTTP do
  @moduledoc false

  @gzip {'content-encoding', 'gzip'}

  def post(url, body, headers) when is_binary(body) do
    headers = [@gzip | Enum.map(headers, fn {k, v} -> {'#{k}', '#{v}'} end)]
    request = {'#{url}', headers, 'application/json', :zlib.gzip(body)}

    with :ok <- maybe_set_proxy(),
         {:ok, {{_, status_code, _}, _headers, body}} <-
           :httpc.request(:post, request, http_options(), []) do
      {:ok, %{status_code: status_code, body: to_string(body)}}
    end
  end

  def post(url, body, headers) do
    case Jason.encode(body) do
      {:ok, body} ->
        post(url, body, headers)

      {:error, message} ->
        NewRelic.log(:debug, "Unable to JSON encode: #{inspect(body)}")
        {:error, message}
    end
  end

  def get(url, headers \\ [], opts \\ []) do
    headers = Enum.map(headers, fn {k, v} -> {'#{k}', '#{v}'} end)
    request = {'#{url}', headers}

    with :ok <- maybe_set_proxy(),
         {:ok, {{_, status_code, _}, _, body}} <-
           :httpc.request(:get, request, http_options(opts), []) do
      {:ok, %{status_code: status_code, body: to_string(body)}}
    end
  end

  @doc """
  Certs are from `CAStore`.
  https://github.com/elixir-mint/castore

  SSL configured according to EEF Security guide:
  https://erlef.github.io/security-wg/secure_coding_and_deployment_hardening/ssl
  """
  def http_options(opts \\ []) do
    [
      connect_timeout: 1000,
      ssl: [
        verify: :verify_peer,
        cacertfile: CAStore.file_path(),
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]
    |> Keyword.merge(opts)
  end

  @spec maybe_set_proxy() :: :ok | {:error, any()}
  defp maybe_set_proxy do
    :new_relic_agent
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:proxy)
    |> case do
      {{host, port}, opts} ->
        host = if is_binary(host), do: String.to_charlist(host), else: host
        port = if is_binary(port), do: String.to_integer(port), else: port

        :httpc.set_options(proxy: {{host, port}, opts})
      _ -> :ok
    end
  end
end
