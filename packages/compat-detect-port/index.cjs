async function detect(port = 0, host) {
  const { findAvailablePort } = await import("@patrickjs/port-manager");
  const result = await findAvailablePort({ port, host });
  return result.port;
}

module.exports = detect;
module.exports.detect = detect;
module.exports.default = detect;

