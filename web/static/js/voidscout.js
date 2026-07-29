(function () {
	"use strict";

	const table = document.querySelector(".void-table");
	if (!table) {
		return;
	}

	const rows = Array.from(table.querySelectorAll("tbody tr[data-pkg-row]"));
	const chips = Array.from(document.querySelectorAll(".filter-chip"));
	const statusEl = document.getElementById("filter-status");
	const filterEmptyRow = document.getElementById("filter-empty-row");
	const serverEmptyRow = document.getElementById("server-empty-row");

	if (rows.length === 0 || chips.length === 0) {
		return;
	}

	let activeFilter = "all";

	function rowMatchesFilter(row, filter) {
		switch (filter) {
			case "updated":
				return row.dataset.updated === "true";
			case "github":
				return row.dataset.upstream === "github";
			case "ftp":
				return row.dataset.upstream === "ftp";
			case "dirlist":
				return row.dataset.upstream === "dirlist";
			case "distfile":
				return row.dataset.distfile === "true";
			default:
				return true;
		}
	}

	function applyFilter(filter) {
		activeFilter = filter;
		let visibleCount = 0;

		rows.forEach(function (row) {
			const visible = rowMatchesFilter(row, filter);
			row.hidden = !visible;
			if (visible) {
				visibleCount += 1;
			}
		});

		chips.forEach(function (chip) {
			const isActive = chip.dataset.filter === filter;
			chip.setAttribute("aria-pressed", isActive ? "true" : "false");
		});

		if (filterEmptyRow) {
			const showFilterEmpty = visibleCount === 0 && filter !== "all";
			filterEmptyRow.hidden = !showFilterEmpty;
		}

		if (serverEmptyRow) {
			serverEmptyRow.hidden = filter !== "all";
		}

		if (statusEl) {
			if (filter === "all") {
				statusEl.textContent = "";
			} else {
				statusEl.textContent =
					visibleCount + " of " + rows.length + " on this page";
			}
		}
	}

	chips.forEach(function (chip) {
		chip.addEventListener("click", function () {
			const filter = chip.dataset.filter || "all";
			if (filter === activeFilter && filter !== "all") {
				applyFilter("all");
				return;
			}
			applyFilter(filter);
		});
	});
})();
