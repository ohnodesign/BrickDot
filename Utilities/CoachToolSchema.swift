import Foundation

/// Tool definitions sent to the Anthropic API.
///
/// Split out of `AIService` so the schema and the executor can be read side by
/// side — every `name` here must have a matching `case` in `CoachToolExecutor`
/// or `CoachToolReader`, and a tier in `CoachToolPolicy`.
///
/// The small builders below exist for the type checker's benefit: a deeply
/// nested `[String: Any]` literal makes Swift's inference crawl (the reason the
/// old inline schema was littered with `as [String: Any]` casts).
enum CoachToolSchema {

    // MARK: - Builders

    private static func prop(_ type: String,
                             _ description: String,
                             values: [String]? = nil) -> [String: Any] {
        var d: [String: Any] = ["type": type, "description": description]
        if let values { d["enum"] = values }
        return d
    }

    private static func idArray(_ description: String) -> [String: Any] {
        let items: [String: Any] = ["type": "string"]
        return ["type": "array", "items": items, "description": description]
    }

    private static func tool(_ name: String,
                             _ description: String,
                             _ properties: [String: Any],
                             required: [String]) -> [String: Any] {
        let schema: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": required
        ]
        return ["name": name, "description": description, "input_schema": schema]
    }

    // MARK: - Read tools

    private static let findTasks = tool(
        "findTasks",
        """
        Search tasks and return matches with their ids. Use this FIRST whenever the \
        user refers to a task in words ("the Cobblestone SW16 photos") — never guess \
        an id. Searches description, service, notes and client name. Completed work \
        is excluded unless status is "done" or "any", so use those to answer questions \
        about finished or billed work.
        """,
        [
            "query": prop("string", "Free text to match against description, service, notes and client name."),
            "client": prop("string", "Optional client name to restrict the search to."),
            "status": prop("string", "Status filter. Defaults to open work only.",
                           values: ["to_do", "in_progress", "done", "open", "any"]),
            "since": prop("string", "Optional earliest service date, yyyy-MM-dd."),
            "until": prop("string", "Optional latest service date, yyyy-MM-dd."),
            "limit": prop("integer", "Maximum results to return. Defaults to 15.")
        ],
        required: []
    )

    private static let getTaskDetail = tool(
        "getTaskDetail",
        "Full detail for one task: every time log, every subtask, expenses, notes, and invoice state. Use before changing a task you are unsure about.",
        ["taskId": prop("string", "Task id from findTasks or the snapshot.")],
        required: ["taskId"]
    )

    private static let listClients = tool(
        "listClients",
        """
        Every client with its shortcode, rate and contact details. The shortcode         is the key that maps outside references to a client — work folders on         disk are named YYYY-MM-DD-<shortcode>-<description>, so this is how you         turn "2026-08-07-cs-photo-…" into Cobblestone Homes without guessing at         the name.
        """,
        [
            "query": prop("string", "Optional filter on name or shortcode. Omit for all clients.")
        ],
        required: []
    )

    private static let getClientSummary = tool(
        "getClientSummary",
        "Totals for a client over a date range: hours logged, task counts by status, how much logged work is not yet linked to an invoice (unlinked, which is not the same as unpaid), and invoiced_amount — work that is on an invoice, counted in the period the work was done rather than the period it was billed. Omit client to summarise every client.",
        [
            "client": prop("string", "Client name. Omit for all clients."),
            "since": prop("string", "Earliest service date, yyyy-MM-dd. Defaults to 30 days ago."),
            "until": prop("string", "Latest service date, yyyy-MM-dd. Defaults to today.")
        ],
        required: []
    )

    private static let listInvoices = tool(
        "listInvoices",
        """
        Invoices on record, newest first: number, title, date, client, and the         work attached to each. Use this to answer what has actually been billed,         and when. Note that an entry with no invoice attached is not necessarily         unbilled — invoicing may have happened outside the app — so report this         as "not linked to an invoice here", never as "unpaid".
        """,
        [
            "client": prop("string", "Optional client name filter."),
            "since": prop("string", "Earliest invoice date, yyyy-MM-dd."),
            "until": prop("string", "Latest invoice date, yyyy-MM-dd."),
            "limit": prop("integer", "Maximum invoices to return. Defaults to 20.")
        ],
        required: []
    )

    // MARK: - Write tools

    private static let addTime = tool(
        "addTime",
        "Log time against a task. Creates a time log entry and adds to the task's total. Use date to backdate work that happened on an earlier day.",
        [
            "taskId": prop("string", "Task id from findTasks."),
            "minutes": prop("number", "Minutes to add. Use 120 for two hours."),
            "date": prop("string", "Day the work happened, yyyy-MM-dd. Defaults to today."),
            "note": prop("string", "Optional short note stored on the time log.")
        ],
        required: ["taskId", "minutes"]
    )

    private static let addSubtask = tool(
        "addSubtask",
        "Add a subtask to a task. Set done to true when logging something already finished.",
        [
            "taskId": prop("string", "Task id from findTasks."),
            "title": prop("string", "Subtask title."),
            "done": prop("boolean", "Whether the subtask is already complete. Defaults to false."),
            "minutes": prop("number", "Optional minutes attributed to this subtask.")
        ],
        required: ["taskId", "title"]
    )

    private static let updateSubtask = tool(
        "updateSubtask",
        "Tick or untick an existing subtask, matched by title within its parent task.",
        [
            "taskId": prop("string", "Parent task id."),
            "title": prop("string", "Existing subtask title (matched case-insensitively, partial allowed)."),
            "done": prop("boolean", "New completion state.")
        ],
        required: ["taskId", "title", "done"]
    )

    private static let createTask = tool(
        "createTask",
        """
        Create a new task for a client. Only use when nothing existing fits —         search with findTasks first.

        Unless the user says what state the task is in, it is filed as a Quick         Capture: an unreviewed note that shows a Quick Capture badge and collects         in its own section, so it is easy to find and sort out later. Pass status         only when the user actually specifies one ("add a todo for…", "log that as         done"), which files it as an ordinary task instead. Any later edit clears         the Quick Capture flag automatically.
        """,
        [
            "client": prop("string", "Client name. Must match an existing client."),
            "description": prop("string", "What the task is."),
            "service": prop("string", "Service category, e.g. PHOTO, WEB, DESIGN. Defaults to the client's usual."),
            "minutes": prop("number", "Optional time to log immediately."),
            "dueDate": prop("string", "Optional due date, yyyy-MM-dd."),
            "status": prop("string", "Initial status. Pass ONLY if the user specified one — omitting it files the task as a Quick Capture.",
                           values: ["to_do", "in_progress", "done"]),
            "quickCapture": prop("boolean", "Override the default. Omit unless the user explicitly asks for or against a Quick Capture.")
        ],
        required: ["client", "description"]
    )

    private static let updateTaskStatus = tool(
        "updateTaskStatus",
        "Change the status of one or more tasks.",
        [
            "taskIds": idArray("Task ids to update."),
            "status": prop("string", "New status.", values: ["to_do", "in_progress", "done"])
        ],
        required: ["taskIds", "status"]
    )

    private static let starTasks = tool(
        "starTasks",
        "Star tasks as high priority. Starred tasks show a star in the entry list and can be isolated with the Starred filter.",
        ["taskIds": idArray("Task ids to star.")],
        required: ["taskIds"]
    )

    private static let unstarTasks = tool(
        "unstarTasks",
        "Remove the star from tasks, returning them to normal priority. Does not change status.",
        ["taskIds": idArray("Task ids to unstar.")],
        required: ["taskIds"]
    )

    private static let updateDueDate = tool(
        "updateDueDate",
        "Set or shift the due date on tasks. Use dueDate for an absolute date, or shift for a relative change.",
        [
            "taskIds": idArray("Task ids to update."),
            "dueDate": prop("string", "Absolute due date, yyyy-MM-dd."),
            "shift": prop("string", "Relative shift.", values: ["tomorrow", "nextWeek", "clear"])
        ],
        required: ["taskIds"]
    )

    private static let startTimer = tool(
        "startTimer",
        "Start the running timer on a task and set it in progress.",
        ["taskId": prop("string", "Task id from findTasks.")],
        required: ["taskId"]
    )

    private static let stopTimer = tool(
        "stopTimer",
        "Stop the running timer on a task and log the elapsed time.",
        ["taskId": prop("string", "Task id from findTasks.")],
        required: ["taskId"]
    )

    private static let bulkUpdate = tool(
        "bulkUpdate",
        "Apply different changes to different tasks in one call. Use when tasks need different updates simultaneously.",
        [
            "updates": [
                "type": "array",
                "description": "One entry per task.",
                "items": [
                    "type": "object",
                    "properties": [
                        "taskId": prop("string", "Task id."),
                        "star": prop("boolean", "Star this task."),
                        "unstar": prop("boolean", "Unstar this task."),
                        "dueDate": prop("string", "Absolute due date, yyyy-MM-dd."),
                        "shift": prop("string", "Relative due date shift.",
                                      values: ["tomorrow", "nextWeek", "clear"]),
                        "status": prop("string", "New status.",
                                       values: ["to_do", "in_progress", "done"])
                    ] as [String: Any],
                    "required": ["taskId"]
                ] as [String: Any]
            ] as [String: Any]
        ],
        required: ["updates"]
    )

    private static let createClient = tool(
        "createClient",
        "Add a new client. Check the existing client list first — never create a near-duplicate of one that already exists under a slightly different name.",
        [
            "name": prop("string", "Client name as it should appear on invoices."),
            "rate": prop("number", "Default hourly rate. Defaults to the app's standard rate."),
            "contactName": prop("string", "Main contact person."),
            "email": prop("string", "Contact email."),
            "phone": prop("string", "Contact phone."),
            "address": prop("string", "Billing address."),
            "shortcode": prop("string", "Short label used in lists, e.g. CS for Cobblestone.")
        ],
        required: ["name"]
    )

    private static let createInvoice = tool(
        "createInvoice",
        """
        Draw uninvoiced work for a client into a new invoice record and assign it         the next sequential invoice number. Marks those entries as billed. Give         either a date range or explicit taskIds. This does NOT render a PDF or         send anything — it creates the record the app's Export screen then works         from. The invoice number is consumed permanently, so confirm the client         and the range before calling.
        """,
        [
            "client": prop("string", "Client name. Must match an existing client."),
            "since": prop("string", "Earliest service date to include, yyyy-MM-dd."),
            "until": prop("string", "Latest service date to include, yyyy-MM-dd."),
            "taskIds": idArray("Specific task ids to invoice instead of a date range."),
            "title": prop("string", "Invoice title. Defaults to a label built from the date range.")
        ],
        required: ["client"]
    )

    // MARK: - Exposed set

    /// Read tools run without confirmation and never mutate the store.
    static let readToolNames: Set<String> = ["findTasks", "getTaskDetail", "getClientSummary", "listClients", "listInvoices"]

    /// Refused over the Claude bridge. In the app these stop for a tap; the
    /// bridge has no confirmation UI, and burning an invoice number — or marking
    /// work billed — with nobody looking is not a mistake you can quietly undo.
    static let appOnlyToolNames: Set<String> = ["createInvoice"]

    static let all: [[String: Any]] = [
        findTasks, getTaskDetail, getClientSummary, listClients, listInvoices,
        addTime, addSubtask, updateSubtask, createTask, createClient, createInvoice,
        updateTaskStatus, starTasks, unstarTasks, updateDueDate,
        startTimer, stopTimer, bulkUpdate
    ]
}
