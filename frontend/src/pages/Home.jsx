// Landing page: short introduction and three quick links.
import { Link } from 'react-router-dom';
import { Card } from '@/components/ui';

const QUICK_LINKS = [
  {
    to: '/trains/search',
    title: 'Search Trains',
    text: 'Find trains between two stations on your travel date and check seat availability.',
  },
  {
    to: '/tickets',
    title: 'PNR Status',
    text: 'Enter your 10-digit PNR to see the current status of every passenger on the ticket.',
  },
  {
    to: '/ops/board',
    title: 'Live Board',
    text: 'See which trains are on time, delayed or cancelled today.',
  },
];

export default function Home() {
  return (
    <div>
      <section className="rounded-lg bg-indigo-900 px-6 py-10 text-white shadow">
        <h1 className="text-3xl font-bold tracking-tight sm:text-4xl">National Railway Reservation &amp; Management System</h1>
        <p className="mt-3 max-w-2xl text-indigo-100">
          Search trains, book tickets with automatic PNR generation, pay securely, cancel with an instant refund
          estimate, and follow live train running status.
        </p>
      </section>

      <div className="mt-6 grid gap-4 sm:grid-cols-3">
        {QUICK_LINKS.map((item) => (
          <Link
            key={item.to}
            to={item.to}
            className="block rounded-lg focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500"
          >
            <Card title={item.title} className="h-full transition-colors hover:border-indigo-400">
              <p className="text-sm text-slate-600">{item.text}</p>
            </Card>
          </Link>
        ))}
      </div>

      <Card title="About this project" className="mt-6">
        <p className="text-sm text-slate-700">
          This is a college DBMS project. The data lives in MySQL (stored procedures, triggers, functions and views do
          the booking, cancellation and refund work) and MongoDB (operations event log). A Spring Boot REST API with
          JWT login sits in between, and this React application is the user interface. It is organised in five
          modules: Train &amp; Route, Passenger &amp; User, Reservation &amp; Seat, Payment &amp; Refund, and Railway
          Operations &amp; Analytics.
        </p>
      </Card>
    </div>
  );
}
