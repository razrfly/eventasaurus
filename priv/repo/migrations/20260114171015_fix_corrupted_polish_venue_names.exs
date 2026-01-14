defmodule EventasaurusApp.Repo.Migrations.FixCorruptedPolishVenueNames do
  @moduledoc """
  Fixes corrupted Polish venue names where diacritical characters were stripped.

  This is a one-time data fix for a historical UTF-8 handling bug that stripped
  Polish characters (ł, ś, ę, ż, ą, ć, ń, ó, ź) from venue names.

  Related: GitHub issue #3212
  """
  use Ecto.Migration

  # Format: {venue_id, corrupted_name, corrected_name}
  # Corrections verified against known Polish spellings
  @corrections [
    # Pałac (Palace) - ł was stripped
    {139, "Paac Potockich", "Pałac Potockich"},
    {142, "Paacyk Sokó", "Pałacyk Sokół"},
    {149, "Paac Radziwiów", "Pałac Radziwiłłów"},
    {158, "Paac Krzysztofory", "Pałac Krzysztofory"},
    {173, "Paac Biskupa Erazma Cioka", "Pałac Biskupa Erazma Ciołka"},
    {178, "Paac Niemiertelnoci", "Pałac Nieśmiertelności"},
    {187, "Paac Sztuki", "Pałac Sztuki"},
    {188, "Paac Pod Baranami", "Pałac Pod Baranami"},
    {249, "Paac Modzieży", "Pałac Młodzieży"},
    {5150, "Paac Kultury i Nauki (pokaż na mapie)", "Pałac Kultury i Nauki (pokaż na mapie)"},
    {5258, "Ogród w Paacu", "Ogród w Pałacu"},
    {16283, "Piwnica Teatralna (Paac Kultury Zagbia)", "Piwnica Teatralna (Pałac Kultury Zagłębia)"},

    # Śląski/Śląska/Śląskie - Ś was stripped
    {247, "Biblioteka lska", "Biblioteka Śląska"},
    {375, "Filharmonia lska", "Filharmonia Śląska"},
    {421, "lski Stadium", "Śląski Stadium"},
    {435, "Teatr lski - Scena w Malarni", "Teatr Śląski - Scena w Malarni"},
    {5153, "Planetarium lskie", "Planetarium Śląskie"},
    {15501, "Tauron Park lski", "Tauron Park Śląski"},
    {886, "ul. Powstaców lskich 126 (pokaż na mapie)", "ul. Powstańców Śląskich 126 (pokaż na mapie)"},

    # Małopolski/Małopolskie - ł was stripped
    {135, "Maopolski Ogród Sztuki", "Małopolski Ogród Sztuki"},
    {176, "Maopolskie Centrum Dźwiku i Sowa", "Małopolskie Centrum Dźwięku i Słowa"},
    {701, "Maopolskie Centrum Nauki Cogiteon", "Małopolskie Centrum Nauki Cogiteon"},
    {16072, "Maopolskie Centrum Kultury SOK", "Małopolskie Centrum Kultury SOK"},

    # Międzynarodowe - ę was stripped
    {171, "Midzynarodowe Centrum Kultury", "Międzynarodowe Centrum Kultury"},
    {222, "Midzynarodowe Centrum Kongresowe", "Międzynarodowe Centrum Kongresowe"},
    {339, "Midzynarodowe Centrum Sztuk Graficznych", "Międzynarodowe Centrum Sztuk Graficznych"},
    {5235, "Midzypokoleniowa Klubokawiarnia Domu Kultury ródmiecie (pokaż na mapie)",
     "Międzypokoleniowa Klubokawiarnia Domu Kultury Śródmieście (pokaż na mapie)"},

    # Ośrodek - Ś was stripped
    {177, "Cricoteka Orodek Dokumentacji Sztuki Tadeusza Kantora",
     "Cricoteka Ośrodek Dokumentacji Sztuki Tadeusza Kantora"},
    {198, "Orodek Kultury im. C.K. Norwida", "Ośrodek Kultury im. C.K. Norwida"},
    {342, "Orodek Ruczaj", "Ośrodek Ruczaj"},
    {374, "Orodek Kultury w Brzeszczach", "Ośrodek Kultury w Brzeszczach"},
    {745, "Orodek Dziaa Twórczych \"Pogodna\" ulica Jana Pawa II25 (pokaż na mapie)",
     "Ośrodek Działań Twórczych \"Pogodna\" ulica Jana Pawła II 25 (pokaż na mapie)"},
    {869, "Orodek Solec Aktywnej Warszawy (pokaż na mapie)",
     "Ośrodek Solec Aktywnej Warszawy (pokaż na mapie)"},
    {4471, "Klub Zgody Orodka Kultury Kraków-Nowa Huta",
     "Klub Zgody Ośrodka Kultury Kraków-Nowa Huta"},
    {15836, "Miejski Orodek Kultury", "Miejski Ośrodek Kultury"},
    {16245, "Miejski Orodek Kultury w Legionowie", "Miejski Ośrodek Kultury w Legionowie"},
    {16295, "Nowodworski Orodek Kultury", "Nowodworski Ośrodek Kultury"},
    {15966, "Godz.18:00 \"W Irandzkim Rytmie\" Nakielski Orodek Kultury - kino Relaks",
     "Godz.18:00 \"W Irańdzkim Rytmie\" Nakielski Ośrodek Kultury - kino Relaks"},

    # Szkoła - ł was stripped
    {189, "Szkoa Muzyczna I i II st. im. B. Rutkowskiego",
     "Szkoła Muzyczna I i II st. im. B. Rutkowskiego"},
    {192, "Szkoa Podstawowa w Biaym Kociele", "Szkoła Podstawowa w Białym Kościele"},
    {232, "Ogólnoksztacca Szkoa Muzyczna I i II st. im. Ignacego Jana Paderewskiego w Tarnowie",
     "Ogólnokształcąca Szkoła Muzyczna I i II st. im. Ignacego Jana Paderewskiego w Tarnowie"},

    # Białoprądnicki - ł, ą were stripped
    {170, "Centrum Kultury Dworek Biaoprdnicki", "Centrum Kultury Dworek Białoprądnicki"},
    {394, "Biaoprdnicki Manor House", "Białoprądnicki Manor House"},

    # Świebodzki - Ś was stripped
    {323, "Hala wiebodzki", "Hala Świebodzki"},
    {794, "ul. wiatowida 17 (pokaż na mapie)", "ul. Światowida 17 (pokaż na mapie)"},

    # Other venue name corrections
    {157, "AST im. Stanisawa Wyspiaskiego w Krakowie  Scena im. S. Wyspiaskiego/Scena 210/Sala 313/Amfiteatr",
     "AST im. Stanisława Wyspiańskiego w Krakowie  Scena im. S. Wyspiańskiego/Scena 210/Sala 313/Amfiteatr"},
    {180, "Akademia Sztuk Piknych w Krakowie", "Akademia Sztuk Pięknych w Krakowie"},
    {221, "Miejski Orodek Kultury w Ldzinach", "Miejski Ośrodek Kultury w Lędzinach"},
    {252, "Zagbiowska Mediateka", "Zagłębiowska Mediateka"},
    {290, "Cybermachina Pozna", "Cybermachina Poznań"},
    {383, "Hala widowiskowo - sportowa Paacu Modzieży",
     "Hala widowiskowo - sportowa Pałacu Młodzieży"},
    {627, "Kozy k. Bielska-Biaej", "Kozy k. Bielska-Białej"},
    {5218, "ksigarnia Fundacji Orodka KARTA (pokaż na mapie)",
     "księgarnia Fundacji Ośrodka KARTA (pokaż na mapie)"},
    {15630, "Warszawa - Biaoka Galeria Pónocna", "Warszawa - Białołęka Galeria Północna"},
    {16103, "owicki Orodek Kultury", "Łowicki Ośrodek Kultury"},
    {16225, "Wodzisawskie Centrum Kultury", "Wodzisławskie Centrum Kultury"},
    {856,
     "Warszawa - ródmiecie, Paac Czapskich, Akademia Sztuk Piknych w Warszawie, ul. Krakowskie Przedmiecie 5 (pokaż na mapie)",
     "Warszawa - Śródmieście, Pałac Czapskich, Akademia Sztuk Pięknych w Warszawie, ul. Krakowskie Przedmieście 5 (pokaż na mapie)"}
  ]

  def up do
    for {id, _corrupted, corrected} <- @corrections do
      escaped = escape_sql(corrected)

      execute("""
      UPDATE venues SET name = '#{escaped}', updated_at = NOW() WHERE id = #{id}
      """)
    end
  end

  def down do
    for {id, corrupted, _corrected} <- @corrections do
      escaped = escape_sql(corrupted)

      execute("""
      UPDATE venues SET name = '#{escaped}', updated_at = NOW() WHERE id = #{id}
      """)
    end
  end

  defp escape_sql(string) do
    String.replace(string, "'", "''")
  end
end
