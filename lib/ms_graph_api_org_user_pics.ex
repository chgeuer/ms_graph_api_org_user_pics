defmodule MsGraphApiOrgUserPics do
  @missing File.read!("assets/missing.svg")
  # @missing Req.get!(url: "https://raw.githubusercontent.com/chgeuer/ms_graph_api_org_user_pics/main/assets/missing.svg").body

  defp fetch_image({name, display_name}, access_token) do
    Req.get!(
       url: "https://graph.microsoft.com/v1.0/users/#{name}/photo/$value",
       auth: {:bearer, access_token})
   |> case do
     %Req.Response{ status: 200,
       headers: %{ "content-type" => [mime_type] },
       body: image_bytes} -> {:ok, String.downcase(name), display_name, image_bytes, mime_type }
      %Req.Response{ status: 404,
       body: %{"error" => %{"code" => "ErrorEntityNotFound"}}} -> {:not_found, String.downcase(name)}
      %Req.Response{ status: 404,
       body: %{"error" => %{"code" => "ImageNotFound"}}} -> {:not_found, String.downcase(name)}
   end
 end

 def fetch_images(org, access_token) do
   org |> Enum.map(&fetch_image(&1, access_token))
 end

 def user(employee, access_token) do
    %Req.Response{
      status: 200,
       body: %{  "userPrincipalName" => name, "displayName" => displayName }
    } = Req.get!(
        url: "https://graph.microsoft.com/v1.0/users/#{employee}",
        auth: {:bearer, access_token})

   {name, displayName}
 end

 def reports(manager, access_token) do
    %Req.Response{
      status: 200,
       body: %{ "value" => value }
    } = Req.get!(
        url: "https://graph.microsoft.com/v1.0/users/#{manager}/directReports",
        auth: {:bearer, access_token})

    value
    |> Enum.map(fn %{"userPrincipalName" => name, "displayName" => display_name} -> {name, display_name} end)
  end

  def org(manager, access_token) do
    manager
    |> user(access_token)
    |> traverse(access_token)
    |> List.flatten()
  end
  defp traverse({name, displayName}, access_token) do
    case reports(name, access_token) do
      map when map == %{} ->
        [{name, displayName}]
      children ->
        x =
          children
          |> Enum.map(&traverse(&1, access_token))
        [ {name, displayName} | x ]
    end
  end

  def kino_view(images) do
    images
    |> Enum.map(fn
      {:ok, _alias, _display_name, image_bytes, mime_type = "image/" <> _ext } ->
        Kino.Image.new(image_bytes, mime_type)
      {:not_found, _alias} ->
        Kino.Image.new(@missing, "image/svg+xml")
    end)
    |> Kino.Layout.grid(columns: 3)
  end

  def email_alias(email), do: email |> String.split("@") |> hd()

  def kino_zip_download(images) do
    zip_contents =
      images
      |> Enum.map(fn
        {:ok, email, display_name, image_bytes, "image/" <> ext } ->
          {~c"#{email_alias(email)} (#{display_name |> String.replace("/", " ")}).#{ext}", image_bytes}
        {:not_found, email} ->
          {~c"missing users/#{email_alias(email)}.svg", @missing }
      end)

    {:ok, {_filename, zip_bytes}} = :zip.create("___.zip", zip_contents, [:memory])
    Kino.Download.new(fn -> zip_bytes end, filename: "user_images.zip", label: "Download the images...")
  end

  def all_in_one(manager_email, access_token) do
    images =
      manager_email
      |> org(access_token)
      |> fetch_images(access_token)

    Kino.Layout.grid([
      images |> kino_zip_download(),
      images |> kino_view()
    ], columns: 1)
  end
end
