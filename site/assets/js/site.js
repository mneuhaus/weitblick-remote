// Weitblick Remote site: screenshot lightbox and copy buttons. Everything works without it.
(() => {
  const text = { close: "Close", copy: "Copy", copied: "Copied" };

  // Lightbox: links with [data-lightbox] open their target image in a <dialog>.
  const links = document.querySelectorAll("a[data-lightbox]");
  if (links.length && typeof HTMLDialogElement === "function") {
    const dialog = document.createElement("dialog");
    dialog.className = "lightbox";
    dialog.innerHTML = '<button type="button" aria-label="' + text.close + '">×</button><img alt=""><p></p>';
    document.body.append(dialog);
    const image = dialog.querySelector("img");
    const caption = dialog.querySelector("p");
    dialog.querySelector("button").addEventListener("click", () => dialog.close());
    dialog.addEventListener("click", (event) => { if (event.target === dialog) dialog.close(); });
    dialog.addEventListener("close", () => { image.removeAttribute("src"); });
    links.forEach((link) => {
      link.addEventListener("click", (event) => {
        if (event.metaKey || event.ctrlKey || event.shiftKey) return;
        event.preventDefault();
        const thumb = link.querySelector("img");
        const dark = link.dataset.dark && matchMedia("(prefers-color-scheme: dark)").matches;
        image.src = dark ? link.dataset.dark : link.href;
        image.alt = thumb ? thumb.alt : "";
        caption.textContent = link.dataset.caption || "";
        dialog.showModal();
      });
    });
  }

  // Copy buttons for terminal snippets.
  document.querySelectorAll(".terminal").forEach((box) => {
    const code = box.querySelector("code");
    if (!code || !navigator.clipboard) return;
    const button = document.createElement("button");
    button.type = "button";
    button.className = "copy";
    button.textContent = text.copy;
    button.addEventListener("click", async () => {
      try {
        await navigator.clipboard.writeText(code.textContent.trim());
        button.textContent = text.copied;
        setTimeout(() => { button.textContent = text.copy; }, 1600);
      } catch { /* clipboard not available: the text stays selectable */ }
    });
    box.append(button);
  });
})();
