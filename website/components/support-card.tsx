import { Mail, ShieldAlert } from 'lucide-react';

export function SupportCard({
  name,
  email,
}: {
  name: 'Oleh Vdovenko';
  email: 'o@olhapi.com';
}) {
  return (
    <div className="rounded-2xl border border-white/10 bg-slate-900/70 p-6 shadow-xl shadow-black/10">
      <div className="flex size-11 items-center justify-center rounded-xl bg-sky-300/8 text-sky-300">
        <Mail aria-hidden="true" />
      </div>
      <h2 className="mt-5 text-lg font-semibold text-white">Contact support</h2>
      <p className="mt-2 text-sm text-slate-400">{name}</p>
      <a
        className="mt-1 inline-block font-medium text-cyan-300 hover:text-cyan-200"
        href={`mailto:${email}`}
      >
        {email}
      </a>
      <div className="mt-6 flex gap-3 border-t border-white/8 pt-5 text-xs leading-5 text-slate-500">
        <ShieldAlert
          className="mt-0.5 size-4 shrink-0 text-rose-300"
          aria-hidden="true"
        />
        <p>
          Never email access tokens, webhook secrets, Home Assistant URLs,
          entity values, or health readings.
        </p>
      </div>
    </div>
  );
}
