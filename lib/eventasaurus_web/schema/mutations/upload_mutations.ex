defmodule EventasaurusWeb.Schema.Mutations.UploadMutations do
  use Absinthe.Schema.Notation

  alias EventasaurusWeb.Resolvers.UploadResolver
  alias EventasaurusWeb.Schema.Middleware.Authenticate

  object :upload_mutations do
    @desc "Upload an image file. Returns the public CDN URL."
    field :upload_image, non_null(:upload_result) do
      arg(:file, non_null(:upload))
      middleware(Authenticate)
      resolve(&UploadResolver.upload_image/3)
    end
  end
end
