defmodule EventasaurusWeb.Services.SvgConversionTest do
  use ExUnit.Case, async: true

  @simple_svg """
  <?xml version="1.0" encoding="UTF-8"?>
  <svg width="100" height="100" xmlns="http://www.w3.org/2000/svg">
    <rect width="100" height="100" fill="red"/>
  </svg>
  """

  describe "SVG to PNG conversion" do
    test "rsvg-convert can convert a simple SVG to PNG" do
      # Create a temporary SVG file
      svg_path = Path.join(System.tmp_dir!(), "test_#{System.unique_integer([:positive])}.svg")
      png_path = String.replace(svg_path, ".svg", ".png")

      try do
        # Write SVG content
        File.write!(svg_path, @simple_svg)

        # Convert using rsvg-convert
        {_output, exit_code} = System.cmd("rsvg-convert", [svg_path, "-o", png_path])

        # Verify the conversion was successful
        assert exit_code == 0
        assert File.exists?(png_path)

        # Verify the PNG file has content
        png_stats = File.stat!(png_path)
        assert png_stats.size > 0
      after
        # Cleanup temporary files
        File.rm(svg_path)
        File.rm(png_path)
      end
    end

    test "rsvg-convert handles missing input file gracefully" do
      non_existent_path = Path.join(System.tmp_dir!(), "non_existent.svg")
      png_path = String.replace(non_existent_path, ".svg", ".png")

      {_output, exit_code} = System.cmd("rsvg-convert", [non_existent_path, "-o", png_path])

      # Should return non-zero exit code for missing file
      assert exit_code != 0
      refute File.exists?(png_path)
    end
  end
end
