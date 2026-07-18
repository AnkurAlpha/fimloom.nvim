local harness = require("tests.helpers")

require("tests.unit.init_spec")(harness)
require("tests.unit.config_spec")(harness)
require("tests.unit.providers_spec")(harness)
require("tests.unit.provider_adapters_spec")(harness)
require("tests.unit.state_spec")(harness)
require("tests.unit.context_spec")(harness)
require("tests.unit.render_spec")(harness)
require("tests.unit.completion_spec")(harness)
require("tests.unit.transport_spec")(harness)

harness.run()
