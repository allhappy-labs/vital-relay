import { ArrowLeftRight, HeartPulse, House } from 'lucide-react';

export function FlowSummary() {
  return (
    <div
      className="mt-12 grid items-stretch gap-4 lg:grid-cols-[1fr_auto_1fr]"
      aria-label="Direct synchronization flow"
    >
      <div className="rounded-3xl border border-rose-300/12 bg-gradient-to-br from-rose-400/10 to-slate-900/70 p-7">
        <div className="flex size-12 items-center justify-center rounded-2xl bg-rose-300/10 text-rose-300">
          <HeartPulse aria-hidden="true" />
        </div>
        <h3 className="mt-8 text-xl font-semibold text-white">Apple Health</h3>
        <p className="mt-2 text-sm leading-6 text-slate-400">
          Selected activity, vitals, sleep, nutrition, workout, and medication
          information.
        </p>
      </div>

      <div className="flex items-center justify-center" aria-hidden="true">
        <div className="flex size-14 items-center justify-center rounded-full border border-white/10 bg-slate-900 text-cyan-300 shadow-xl">
          <ArrowLeftRight />
        </div>
      </div>

      <div className="rounded-3xl border border-sky-300/12 bg-gradient-to-br from-sky-400/10 to-slate-900/70 p-7">
        <div className="flex size-12 items-center justify-center rounded-2xl bg-sky-300/10 text-sky-300">
          <House aria-hidden="true" />
        </div>
        <h3 className="mt-8 text-xl font-semibold text-white">
          Your Home Assistant
        </h3>
        <p className="mt-2 text-sm leading-6 text-slate-400">
          The instance and Health Bridge integration you configure and operate
          yourself.
        </p>
      </div>
    </div>
  );
}
