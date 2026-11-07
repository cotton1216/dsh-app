import { test } from "node:test";
import assert from "node:assert/strict";
import net from "node:net";
import { mkdtemp, lstat, readdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { apply } from "../bridge/desktop-pairing.mjs";

test("pairing uses an owner-only socket and no credential file", async () => {
  const home = await mkdtemp(join(tmpdir(), "dsh-pair-"));
  const previous = process.env.DSH_HOME;
  process.env.DSH_HOME = home;
  let dispose;
  const ctx = {
    webServer: { port: 54829, protocol: "http:" },
    connection: { authenticatedUrl: (url) => `${url}?token=test-only` },
    on: (event, fn) => { assert.equal(event, "dispose"); dispose = fn; },
  };
  try {
    await apply(ctx);
    const dir = join(home, "phone-pairing");
    const path = join(dir, "host.sock");
    assert.equal((await lstat(dir)).mode & 0o777, 0o700);
    assert.equal((await lstat(path)).mode & 0o777, 0o600);
    assert.deepEqual(await readdir(dir), ["host.sock"]);
    const data = await new Promise((resolve, reject) => {
      const socket = net.connect(path);
      let text = "";
      socket.on("data", (chunk) => { text += chunk; });
      socket.on("end", () => resolve(JSON.parse(text)));
      socket.on("error", reject);
    });
    assert.equal(data.pid, process.pid);
    assert.equal(data.url, "http://127.0.0.1:54829/?token=test-only");
    // A second instance must fail rather than unlink the first socket.
    await assert.rejects(apply(ctx), { code: "EADDRINUSE" });
  } finally {
    await dispose?.();
    if (previous === undefined) delete process.env.DSH_HOME;
    else process.env.DSH_HOME = previous;
  }
});
