defmodule EventasaurusDiscovery.VenueImages.TriviaAdvisorImageUploadJobTest do
  use EventasaurusApp.DataCase, async: true

  alias EventasaurusDiscovery.VenueImages.TriviaAdvisorImageUploadJob

  describe "enqueue/1" do
    test "enqueues job with required parameters" do
      assert {:ok, job} =
               TriviaAdvisorImageUploadJob.enqueue(
                 venue_id: 123,
                 venue_slug: "three-johns-angel",
                 trivia_advisor_images: [
                   %{
                     "local_path" =>
                       "/uploads/google_place_images/three-johns-angel/original_google_place_1.jpg"
                   }
                 ]
               )

      assert job.worker ==
               "EventasaurusDiscovery.VenueImages.TriviaAdvisorImageUploadJob"

      assert job.queue == "venue_enrichment"
      assert job.args["venue_id"] == 123
      assert job.args["venue_slug"] == "three-johns-angel"
      assert length(job.args["trivia_advisor_images"]) == 1
    end

    test "raises ArgumentError when venue_id is missing" do
      assert_raise ArgumentError,
                   "venue_id, venue_slug, and trivia_advisor_images are required",
                   fn ->
                     TriviaAdvisorImageUploadJob.enqueue(
                       venue_slug: "test",
                       trivia_advisor_images: []
                     )
                   end
    end

    test "raises ArgumentError when venue_slug is missing" do
      assert_raise ArgumentError,
                   "venue_id, venue_slug, and trivia_advisor_images are required",
                   fn ->
                     TriviaAdvisorImageUploadJob.enqueue(
                       venue_id: 123,
                       trivia_advisor_images: []
                     )
                   end
    end

    test "raises ArgumentError when trivia_advisor_images is missing" do
      assert_raise ArgumentError,
                   "venue_id, venue_slug, and trivia_advisor_images are required",
                   fn ->
                     TriviaAdvisorImageUploadJob.enqueue(
                       venue_id: 123,
                       venue_slug: "test"
                     )
                   end
    end

    test "accepts optional match metadata" do
      assert {:ok, job} =
               TriviaAdvisorImageUploadJob.enqueue(
                 venue_id: 123,
                 venue_slug: "three-johns-angel",
                 trivia_advisor_images: [%{"local_path" => "/test.jpg"}],
                 match_tier: "slug_geo",
                 confidence: 1.0
               )

      assert job.args["match_tier"] == "slug_geo"
      assert job.args["confidence"] == 1.0
    end
  end

  describe "job metadata" do
    test "sets correct worker name" do
      {:ok, job} =
        TriviaAdvisorImageUploadJob.enqueue(
          venue_id: 123,
          venue_slug: "test",
          trivia_advisor_images: []
        )

      assert job.worker ==
               "EventasaurusDiscovery.VenueImages.TriviaAdvisorImageUploadJob"
    end

    test "sets correct queue" do
      {:ok, job} =
        TriviaAdvisorImageUploadJob.enqueue(
          venue_id: 123,
          venue_slug: "test",
          trivia_advisor_images: []
        )

      assert job.queue == "venue_enrichment"
    end

    test "sets priority to 2" do
      {:ok, job} =
        TriviaAdvisorImageUploadJob.enqueue(
          venue_id: 123,
          venue_slug: "test",
          trivia_advisor_images: []
        )

      assert job.priority == 2
    end

    test "converts keyword args to string keys" do
      {:ok, job} =
        TriviaAdvisorImageUploadJob.enqueue(
          venue_id: 123,
          venue_slug: "test",
          trivia_advisor_images: []
        )

      # Verify all keys are strings
      assert is_binary(hd(Map.keys(job.args)))
    end
  end
end
