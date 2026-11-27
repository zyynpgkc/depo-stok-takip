import Link from "next/link";

export default function Home() {
  return (
    <main className="mx-auto flex w-full max-w-md flex-1 flex-col gap-8 px-4 py-8">
      <h1 className="text-center text-3xl font-bold tracking-tight">
        Depo Stok Takip
      </h1>
      <nav className="flex flex-col gap-4">
        <Link
          href="/giris"
          className="flex min-h-16 items-center justify-center rounded-2xl bg-zinc-900 px-4 text-xl font-semibold text-white active:bg-zinc-700"
        >
          Stok Giriş
        </Link>
        <Link
          href="/cikis"
          className="flex min-h-16 items-center justify-center rounded-2xl bg-zinc-900 px-4 text-xl font-semibold text-white active:bg-zinc-700"
        >
          Stok Çıkış
        </Link>
        <Link
          href="/transfer"
          className="flex min-h-16 items-center justify-center rounded-2xl bg-zinc-900 px-4 text-xl font-semibold text-white active:bg-zinc-700"
        >
          Transfer
        </Link>
        <Link
          href="/sorgu"
          className="flex min-h-16 items-center justify-center rounded-2xl bg-zinc-900 px-4 text-xl font-semibold text-white active:bg-zinc-700"
        >
          Sorgula
        </Link>
      </nav>
    </main>
  );
}
