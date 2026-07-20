export default function Avatar({
  user,
  photo,
  name,
  className = "h-9 w-9 rounded-xl",
  textClassName = "text-sm",
}) {
  const displayName = name || user?.farmName || user?.name || "?";
  const image = photo || user?.photo || null;
  const url = typeof image === "string" ? image : image?.url;

  if (url) {
    return (
      <img
        src={url}
        alt=""
        className={`${className} shrink-0 object-cover`}
      />
    );
  }

  return (
    <div
      className={`grid ${className} shrink-0 place-items-center bg-harvest-500 text-white font-bold ${textClassName}`}
    >
      {displayName.charAt(0).toUpperCase()}
    </div>
  );
}
