project('singularity-weather', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-weather"', language: 'c')
subdir('po')

gtk_dep   = dependency('gtk4')
gee_dep   = dependency('gee-0.8')
json_dep  = dependency('json-glib-1.0')
soup_dep  = dependency('libsoup-3.0')
m_dep     = meson.get_compiler('c').find_library('m', required: false)

libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

core_sources = files(
  'src/model.vala',
  'src/service.vala',
)

executable('singularity-weather',
  core_sources + files(
    'src/app.vala',
    'src/window.vala',
    'src/charts.vala',
    'src/snapshot.vala',
    'src/search.vala',
    'src/forecast_bus.vala',
  ),
  dependencies: [gtk_dep, gee_dep, json_dep, soup_dep, m_dep, libsingularity_dep],
  install: true
)

model_test = executable('weather-test',
  core_sources + files('tests/model_test.vala'),
  dependencies: [gee_dep, json_dep, soup_dep, m_dep, dependency('gio-2.0')],
)
test('weather', model_test)

shared_module('singularity-weather-widget',
  files('widget/forecast_widget.vala'),
  dependencies: [gtk_dep, gee_dep, json_dep, libsingularity_dep],
  install: true,
  install_dir: get_option('libdir') / 'singularity' / 'widgets'
)
install_data('widget/dev.sinty.weather.forecast.widget',
  install_dir: get_option('datadir') / 'singularity' / 'widgets'
)

install_data('data/search-providers/dev.sinty.weather.ini',
  install_dir: get_option('datadir') / 'singularity' / 'search-providers'
)

service_conf = configuration_data()
service_conf.set('bindir', get_option('prefix') / get_option('bindir'))
configure_file(
  input: 'data/dev.sinty.weather.service.in',
  output: 'dev.sinty.weather.service',
  configuration: service_conf,
  install: true,
  install_dir: get_option('datadir') / 'dbus-1' / 'services'
)

install_data('data/capabilities/dev.sinty.Weather1.ini',
  install_dir: get_option('datadir') / 'singularity' / 'capabilities'
)

install_data('data/dev.sinty.weather.desktop',
  install_dir: get_option('datadir') / 'applications'
)

install_data('data/dev.sinty.weather.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)

install_data('data/dev.sinty.weather.json',
  install_dir: get_option('datadir') / 'singularity' / 'app-settings'
)

install_data('data/icons/dev.sinty.weather.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)
