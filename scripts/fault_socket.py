"""Local QA fault injection: accept TCP but never send a response, no fake results."""

import asyncio


async def accept(reader, writer):
    try:
        await asyncio.sleep(40)
    finally:
        writer.close()
        await writer.wait_closed()


async def main():
    server = await asyncio.start_server(accept, "127.0.0.1", 8001)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
