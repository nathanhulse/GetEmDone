import { buildApp } from "./app.js";

const { app } = buildApp();
await app.listen({ port: Number(process.env.PORT ?? 3000), host: process.env.HOST ?? "127.0.0.1" });

