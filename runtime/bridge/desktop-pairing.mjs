// Opt-in desktop pairing. Loaded inside the existing Host; never starts an engine.
// Only the local OS user (or that user over SSH) may read the Unix socket.
// The startup token is sent in memory, never written to disk or logs.
import net from "node:net";
import { mkdir, lstat, chmod } from "node:fs/promises";
import { join } from "node:path";
import { homedir } from "node:os";

export const name = "dsh-go-desktop-pairing";
export const inject = ["connection", "webServer"];

export async function apply(ctx) {
  const home = process.env.DSH_HOME || join(homedir(), ".dsh");
  const dir = join(home, "phone-pairing");
  await mkdir(dir, { mode: 0o700 }).catch((error) => {
    if (error.code !== "EEXIST") throw error;
  });
  const stat = await lstat(dir);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid()) {
    throw new Error("Pairing directory must be owned by the current user");
  }
  await chmod(dir, 0o700);
  const path = join(dir, "host.sock");
  // Do not unlink an existing endpoint: another plugin instance may own it.
  const clients = new Set();
  const server = net.createServer((socket) => {
    clients.add(socket);
    socket.on("close", () => clients.delete(socket));
    socket.on("error", () => socket.destroy());
    socket.setTimeout(3000, () => socket.destroy());
    const port = ctx.webServer.port;
    if (!Number.isInteger(port) || port < 1 || port > 65535 || ctx.webServer.protocol !== "http:") {
      socket.end(JSON.stringify({ error: "backend_unavailable" }) + "\n");
      return;
    }
    const url = ctx.connection.authenticatedUrl(`http://127.0.0.1:${port}/`);
    socket.end(JSON.stringify({ version: 1, pid: process.pid, url }) + "\n");
  });
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(path, () => { server.off("error", reject); resolve(); });
  });
  await chmod(path, 0o600);
  server.on("error", () => { for (const socket of clients) socket.destroy(); });
  ctx.on("dispose", () => {
    for (const socket of clients) socket.destroy();
    return new Promise((resolve) => server.close(resolve));
  });
}
