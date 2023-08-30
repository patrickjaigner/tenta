export function NetworkCard(props: {
  networkName: string;
  networkIdentifier: string;
}) {
  // TODO: pull sensorCount from SWR

  const sensorCount: number = 17;

  return (
    <div className="flex flex-col w-full overflow-hidden bg-white border rounded-lg shadow border-slate-200">
      <h2 className="flex flex-row items-baseline px-3 pt-2 pb-1 m-0 text-lg font-bold border-b border-slate-200">
        <div>{props.networkName}</div>
        <div className="flex-grow" />
        <div className="px-1 text-sm font-medium text-teal-800 bg-teal-200 rounded">
          <span className="font-bold text-teal-900">{sensorCount}</span> sensor
          {sensorCount === 1 ? "" : "s"}
        </div>
      </h2>
      <div className="flex flex-col w-full p-3 bg-white">
        <p className="text-xs">identifier: {props.networkIdentifier}</p>
      </div>
    </div>
  );
}