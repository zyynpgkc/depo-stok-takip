import Link from "next/link";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Stok Çıkış",
};

export default function CikisPage() {
  return (
    <main className="mx-auto flex w-full max-w-md flex-1 flex-col gap-8 px-4 py-8">
      <h1 className="text-center text-3xl font-bold">Stok Çıkış</h1>
      <Link href="/" className="text-center text-lg font-medium underline">
        Ana sayfaya dön
      </Link>
    </main>
  );
}
