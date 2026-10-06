using Singularity.Apps.Weather;

const string SAMPLE = """{"latitude":45.46,"longitude":9.18,"utc_offset_seconds":7200,"timezone":"Europe/Rome",
"current":{"time":"2026-09-26T14:15","temperature_2m":21.4,"apparent_temperature":20.1,"relative_humidity_2m":55,"is_day":1,"weather_code":2,"wind_speed_10m":12.3,"wind_direction_10m":225,"wind_gusts_10m":25.0,"pressure_msl":1014.2,"precipitation":0.0},
"hourly":{"time":["2026-09-26T13:00","2026-09-26T14:00","2026-09-26T15:00","2026-09-26T16:00"],"temperature_2m":[20.5,21.4,22.0,21.1],"precipitation_probability":[0,5,40,null],"weather_code":[1,2,61,3],"is_day":[1,1,1,1],"visibility":[24000,20000,18000,15000],"uv_index":[4.1,3.5,2.0,1.0]},
"daily":{"time":["2026-09-26","2026-09-27"],"weather_code":[61,0],"temperature_2m_max":[23.0,25.5],"temperature_2m_min":[14.2,13.0],"sunrise":["2026-09-26T07:12","2026-09-27T07:13"],"sunset":["2026-09-26T19:08","2026-09-27T19:06"],"daylight_duration":[42960,42780],"uv_index_max":[4.5,5.0],"precipitation_sum":[3.2,0.0],"precipitation_probability_max":[70,0]}}""";

void test_parse () {
    Forecast f;
    try {
        f = Forecast.parse (SAMPLE);
    } catch (Error e) {
        error ("parse: %s", e.message);
    }
    assert (f.timezone_name == "Europe/Rome");
    assert (f.current_time.get_hour () == 14 && f.current_time.get_utc_offset () == 2 * TimeSpan.HOUR);
    assert (f.temperature == 21.4 && f.humidity == 55 && f.code == 2 && f.is_day);
    assert (f.hours.size == 3);
    assert (f.hours[0].time.get_hour () == 14);
    assert (f.hours[1].precipitation_probability == 40);
    assert (f.hours[2].precipitation_probability == 0);
    assert (f.visibility == 20000 && f.uv == 3.5);
    assert (f.days.size == 2);
    assert (f.days[0].sunrise.get_hour () == 7 && f.days[0].sunset.get_minute () == 8);
    assert (f.days[1].high == 25.5);
    double p = Forecast.sun_progress (f.current_time, f.days[0].sunrise, f.days[0].sunset);
    assert (p > 0.55 && p < 0.62);
    assert (Forecast.sun_progress (f.days[0].sunrise.add_minutes (-5), f.days[0].sunrise, f.days[0].sunset) < 0);
    assert (Forecast.sun_progress (f.days[0].sunset.add_minutes (5), f.days[0].sunrise, f.days[0].sunset) > 1);
}

void test_errors () {
    bool failed = false;
    try {
        Forecast.parse ("{\"error\":true,\"reason\":\"Latitude must be in range\"}");
    } catch (Error e) {
        failed = e.message.contains ("Latitude");
    }
    assert (failed);
}

void test_coordinates () {
    var p = Place.from_coordinates ("45.4642, 9.19");
    assert (p != null && (p.latitude - 45.4642).abs () < 1e-6 && (p.longitude - 9.19).abs () < 1e-6);
    p = Place.from_coordinates ("-33,87; 151,21");
    assert (p != null && p.latitude < -33.8 && p.longitude > 151.2);
    assert (Place.from_coordinates ("Milano") == null);
    assert (Place.from_coordinates ("95, 10") == null);
    assert (Place.from_coordinates ("45, 190") == null);
    assert (new Place ("A", "", "", -12.5, -45.25).coordinates () == "12.50°S, 45.25°W");

}

void test_places_json () {
    string json = """{"results":[{"name":"Milan","latitude":39.2,"longitude":-89.5,"country":"United States","population":1800},{"name":"Milano","latitude":45.46,"longitude":9.19,"country":"Italia","admin1":"Lombardia","population":1371498},{"latitude":1}]}""";
    try {
        var list = WeatherService.parse_places (json);
        assert (list.size == 2);
        var ranked = WeatherService.rank (list, "milano");
        assert (ranked[0].subtitle () == "Lombardia, Italia");
        ranked = WeatherService.rank (list, "Milan");
        assert (ranked[0].subtitle () == "United States");
        var accents = new Gee.ArrayList<Place> ();
        var small = new Place ("Zürich", "", "Schweiz", 47.37, 8.54);
        var big = new Place ("Zurichberg", "", "Schweiz", 47.38, 8.56);
        big.population = 900000;
        accents.add (big);
        accents.add (small);
        assert (WeatherService.rank (accents, "zurich")[0].name == "Zürich");
        assert (WeatherService.parse_places ("{\"generationtime_ms\":0.5}").size == 0);
    } catch (Error e) {
        error ("places: %s", e.message);
    }
}

void test_conditions () {
    int[] codes = { 0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99 };
    foreach (int code in codes) {
        var c = Conditions.describe (code, true);
        assert (c.icon.has_prefix ("weather-") && c.label != "Unknown");
    }
    assert (Conditions.describe (0, false).icon == "weather-clear-night");
    assert (Conditions.compass (0) == "N" && Conditions.compass (225) == "SW" && Conditions.compass (359) == "N" && Conditions.compass (-90) == "W");
    assert (Conditions.uv_level (2) == "Low" && Conditions.uv_level (11) == "Extreme");
    assert (Format.duration (42960) == "11h 56m");
}

bool comma_locale () {
    foreach (string name in new string[] { "it_IT.UTF-8", "de_DE.UTF-8", "fr_FR.UTF-8" }) {
        if (Intl.setlocale (LocaleCategory.NUMERIC, name) != null && "%.1f".printf (1.5) == "1,5") return true;
    }
    Intl.setlocale (LocaleCategory.NUMERIC, "C");
    return false;
}

void test_url () {
    if (!comma_locale ()) {
        Test.skip ("no locale with a decimal comma is installed");
        return;
    }
    assert (new Place ("A", "", "", 45.46427, 9.18951).id == "45.4643,9.1895");
    string url = WeatherService.forecast_url (new Place ("x", "", "", 45.5, -9.25), Units.IMPERIAL);
    assert (url.contains ("latitude=45.5000&longitude=-9.2500"));
    assert (url.contains ("temperature_unit=fahrenheit"));
    Intl.setlocale (LocaleCategory.NUMERIC, "C");
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C");
    Test.init (ref args);
    Test.add_func ("/weather/parse", test_parse);
    Test.add_func ("/weather/errors", test_errors);
    Test.add_func ("/weather/coordinates", test_coordinates);
    Test.add_func ("/weather/places", test_places_json);
    Test.add_func ("/weather/conditions", test_conditions);
    Test.add_func ("/weather/url", test_url);
    return Test.run ();
}
