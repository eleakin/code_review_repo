# =============================================================================
# DETR R&A PDF Maker — FULL APP with Login + Blue Header
# =============================================================================
# - Full-screen login (loads users from Credentials.R/credentials.R/cresentials_R.txt)
# - Blue header (navbar + logo) with white text/icons
# - NAICS Picker with 3 selectize inputs + two copy-to-clipboard text boxes
# - Paste screenshots (Ctrl+V) → build paginated PDF with header/body + footer
# - Notes box: rendered as a full 7x5 panel like a screenshot (CENTERED TEXT)
# - Save PDFs to Downloads\DataDump; Upload to DFC (nested 2-digit path)
# - Uploaded file name appends logged-in user's first name
# - Add new (Situs, Description, NAICS) to CSV and keep choices synced
# =============================================================================

library(shiny)
library(shinydashboard)
library(grid)
library(base64enc)
library(png)
library(readr)
library(dplyr)

# =============================================================================
# Credentials loader
# =============================================================================
users <- NULL
cred_paths <- c("Credentials.R", "credentials.R", "cresentials_R.txt")
for (p in cred_paths) {
  if (file.exists(p)) {
    try(source(p, local = TRUE), silent = TRUE)   # should define `users`
    if (exists("users", inherits = FALSE) && is.data.frame(users)) break
  }
}
# Fallback demo user if no credentials file found (real users belong in
# Credentials.R, which is never committed to source control)
if (!exists("users", inherits = FALSE) || !is.data.frame(users)) {
  users <- data.frame(
    username    = "demo",
    password    = "demo",
    scan_folder = "Demo Scans",
    stringsAsFactors = FALSE
  )
}

auth_ok <- function(u, p, df) {
  if (!nzchar(u) || !nzchar(p) || !is.data.frame(df) || nrow(df) == 0) return(FALSE)
  any(df$username == u & df$password == p)
}

# =============================================================================
# Paths, helpers, and dataset utilities
# =============================================================================
data_path   <- "NAICS_CODES_20250810.csv"
default_dir <- "~/Downloads"
dd2_dir     <- "R:/RAFileCabinet"
dir.create(default_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(dd2_dir,     showWarnings = FALSE, recursive = TRUE)

sanitize_filename <- function(x) {
  x <- trimws(x)
  x <- gsub('[\\/:*?"<>|]', "_", x)
  x <- gsub("\\s+", " ", x)
  if (!nzchar(x)) x <- "document"
  x
}

digits_10 <- function(x) {
  raw <- if (is.null(x)) "" else as.character(x)
  ds  <- gsub("\\D", "", raw)
  if (nchar(ds) > 10) ds <- substr(ds, nchar(ds)-9, nchar(ds))
  if (nchar(ds) == 0) return("")
  paste0(strrep("0", 10 - nchar(ds)), ds)
}

nested_2digit_path <- function(base_dir, ten_digits) {
  if (!nzchar(ten_digits) || nchar(ten_digits) != 10) {
    segs <- rep("00", 5)
  } else {
    segs <- substring(ten_digits, seq(1, 9, by = 2), seq(2, 10, by = 2))
  }
  do.call(file.path, as.list(c(base_dir, as.list(segs))))
}

ensure_dataset <- function(path) {
  if (!file.exists(path)) {
    df0 <- tibble::tibble(Situs = character(), Description = character(), NAICS = character())
    readr::write_csv(df0, path, na = "")
    return(df0)
  }
  dat <- tryCatch(
    readr::read_csv(path, col_types = readr::cols(.default = readr::col_character()), show_col_types = FALSE),
    error = function(e) tibble::tibble()
  )
  nm <- names(dat)
  nm_norm <- toupper(trimws(nm))
  for (i in seq_along(nm_norm)) {
    if (nm_norm[i] == "SITUS") nm[i] <- "Situs"
    if (nm_norm[i] == "DESCRIPTION") nm[i] <- "Description"
    if (nm_norm[i] == "NAICS") nm[i] <- "NAICS"
  }
  names(dat) <- nm
  need <- c("Situs","Description","NAICS")
  for (m in setdiff(need, names(dat))) dat[[m]] <- character()
  dat <- dat[, need]
  tibble::as_tibble(dat)
}

clean_choices <- function(x) {
  x <- as.character(x); x[is.na(x)] <- ""; x <- trimws(x); x <- x[nzchar(x)]
  sort(unique(x))
}

# =============================================================================
# LOGIN UI
# =============================================================================
login_ui <- function(msg = NULL) {
  fluidPage(
    tags$head(
      tags$style(HTML("
        html, body { height:100%; background: #304d8c; }
        .login-wrapper { display:flex; align-items:center; justify-content:center; height:100vh; }
        .login-card { background:#ffffff; width: 480px; border-radius:16px; padding:28px 28px 20px;
                      box-shadow: 0 12px 40px rgba(0,0,0,0.25); }
        .login-title { font-size:22px; font-weight:700; color:#304d8c; margin-bottom:18px; }
        .login-sub   { font-size:13px; color:#304d8c; margin-bottom:16px; }
        .btn-wide    { width:100%; }
        .msg { margin-top:10px; color:#b91c1c; font-weight:600; }
        .footer-note { text-align:center; color:#1e3a8a; font-size:12px; margin-top:14px; }
      "))
    ),
    div(class="login-wrapper",
        div(class="login-card",
            div(class="login-title","DETR R&A Workflow App – Sign In"),
            div(class="login-sub","Please enter your username and password."),
            textInput("login_user", "Username", width = "100%"),
            passwordInput("login_pass", "Password", width = "100%"),
            actionButton("do_login", "Sign in", class = "btn btn-primary btn-wide"),
            if (!is.null(msg) && nzchar(msg)) div(class="msg", msg),
            div(class="footer-note",
                HTML("V 6.0 BETA · Nevada DETR R&amp;A"))
        )
    )
  )
}

# =============================================================================
# MAIN UI (dashboard)
# =============================================================================
main_app_ui <- dashboardPage(
  skin = "blue",
  dashboardHeader(
    title = span("DETR R&A Workflow App", style = "color: white; font-weight: bold;"), 
    titleWidth = 300, 
    tags$li(class = "dropdown", 
            style = "padding:8px;",  
            actionLink("do_logout", label = "Log out", icon = icon("right-from-bracket")))
  ),
  dashboardSidebar(
    width = 250,
    div(style="text-align:center;",
        textInput("top_text", "UI Account Number", value = "", width = "90%")
    ),
    div(style="text-align:center;",
        textInput("file_name", "File Name", "NOTES_0000000000.pdf", width = "90%")
    ),
    # Create PDF button
    actionButton("make_pdf", "Create PDF",
                 style = "margin-top:6px; width:180px; background-color:orange; color:blue; font-weight:bold;"),
    # >>> MOVED: Clear buttons directly below Create PDF <<<
    actionButton("clear_body",  "Clear NAICS & Situs Data",
                 style = "margin-top:6px; width:180px; background-color:blue; color:white; font-weight:bold;"),
    actionButton("clear_shots", "Clear All Screenshots",
                 style = "margin-top:6px; width:180px; background-color:green; color:white; font-weight:bold;"),
    actionButton("clear_all", "Clear All Data",
                 style = "margin-top:6px; width:180px; background-color:purple; color:white; font-weight:bold;"),
    # Overwrite checkbox now below the clears
    checkboxInput("overwrite", "Overwrite if file exists", FALSE),
    # Text areas
    div(style="text-align:center;",
        textAreaInput("body_text", "NAICS and Situs Data", "", width = "90%", height = "120px")
    ),
    div(style="text-align:center; margin-top:10px;",
        textAreaInput("notes_text", "Paste Notes Here", "",
                      width = "90%", height = "120px")
    ),
    # Paste zone
    div(style="text-align:center; margin-top:10px;", p(tags$b("Paste Screenshots Here"))),
    div(style = "display:flex; justify-content:center; margin-bottom:10px;",
        tags$div(
          id = "pasteZone", contenteditable = "true",
          style = "width:85%; height:80px; border:2px solid #3c8dbc; border-square:6px; padding:10px; background:#f0f7ff; color:#2c3e50; overflow:auto;",
          "Paste Images (Ctrl+V)."
        )
    ),
    div(style="margin-top:6px; font-size:13px; color:#2c3e50; text-align:center;",
        strong("Screenshots pasted: "), uiOutput("shot_count", inline=TRUE))
  ),
  dashboardBody(
    tags$style(HTML("
      .content-wrapper { background:#f7f9fc; }
      .box { border-top-color:#3c8dbc; }
      .btn-row .btn { margin-right:8px; margin-bottom:8px; }
      .detr-logo { position: fixed; right: 12px; bottom: 12px; width: 180px; height: auto; z-index: 1000; opacity: 0.98; pointer-events: none; }
      .copy-row { display:flex; align-items:center; }
      .naics-box .box-body { max-height: 260px; overflow-y: auto; }
      #out_str { width:480px !important; min-width:480px; max-width:480px; }
      #situs_desc_input { width:480px !important; min-width:480px; max-width:480px; }
      .copy-row .btn { margin-left:4px; }
      .app-footer { text-align:center; color:#1e3a8a; font-size:12px; padding:10px 8px 14px; margin-top:12px; border-top:1px solid #e5e7eb; }
    ")),
    # Paste handlers
    tags$script(HTML("
      (function() {
        const zone=document.getElementById('pasteZone');
        if(!zone) return;
        zone.addEventListener('paste', function(e){
          if(!e.clipboardData||!e.clipboardData.items) return;
          for(let i=0;i<e.clipboardData.items.length;i++){
            const it=e.clipboardData.items[i];
            if(it.type && it.type.indexOf('image')!==-1){
              const blob=it.getAsFile();
              const r=new FileReader();
              r.onload=function(evt){
                Shiny.setInputValue('pasted_image',evt.target.result,{priority:'event'});
              };
              r.readAsDataURL(blob);
              e.preventDefault();
            }
          }
        });
      })();
    ")),
    tags$script(HTML("
      Shiny.addCustomMessageHandler('clearPasteZone', function(){
        var z = document.getElementById('pasteZone');
        if(z){ z.innerHTML = 'Paste Images (Ctrl+V).'; }
      });
    ")),
    
    # NAICS Picker + copy fields
    fluidRow(
      box(width=12, title="NAICS Picker Tool", status="primary", solidHeader=TRUE, class="naics-box",
          fluidRow(
            column(4, selectizeInput("selA", "Situs-Location", choices = NULL,
                                     options = list(create = TRUE, placeholder = "Type to search or add..."))),
            column(4, selectizeInput("selB", "BLS NAICS Description", choices = NULL,
                                     options = list(create = TRUE, placeholder = "Type to search or add..."))),
            column(4, selectizeInput("selC", "NAICS Code", choices = NULL,
                                     options = list(create = TRUE, placeholder = "Type to search or add...")))
          ),
          tags$hr(),
          div(class="copy-row",
              textInput("out_str", label = "Data to copy into the PDF", value = "", placeholder = "Situs - Description - NAICS"),
              actionButton("copy_btn", "Copy", class = "btn btn-default")
          ),
          tags$script(HTML("
            (function(){
              $(document).on('click', '#copy_btn', function(){
                var el = document.getElementById('out_str');
                el.select(); el.setSelectionRange(0, 99999);
                document.execCommand('copy');
                Shiny.setInputValue('copied', Date.now(), {priority:'event'});
              });
            })();
          ")),
          div(style="margin-top:10px;",
              div(class="copy-row",
                  textInput("situs_desc_input", label = "Data to copy into QUEST Notes", value = "", placeholder = "Situs - Description"),
                  actionButton("copy_situs_desc", "Copy", class = "btn btn-default")
              )
          ),
          tags$script(HTML("
            (function(){
              $(document).on('click', '#copy_situs_desc', function(){
                var el = document.getElementById('situs_desc_input');
                if (!el) return;
                el.select(); el.setSelectionRange(0, 99999);
                document.execCommand('copy');
                Shiny.setInputValue('copied_situs_desc', Date.now(), {priority:'event'});
              });
            })();
          ")),
          selectInput("recent_copies", "Recent copies (last 5)", choices = character(0), selected = NULL, width = "100%"),
          tags$hr(),
          actionButton("add_row", "Add to NAICS dataset",
                       style = "margin-top:6px; width:180px; background-color:green; color:white; font-weight:bold;"),
          uiOutput("add_status")
      )
    ),
    
    fluidRow(valueBoxOutput("shot_box", width = 12)),
    fluidRow(
      box(width=12, title="PDF Creation Status", status="primary", solidHeader=TRUE,
          verbatimTextOutput("status"),
          div(class = "btn-row",
              downloadButton("download_pdf","Download PDF"),
              actionButton("open_pdf","Open PDF"))
      )
    ),
    
    fluidRow(
      box(width=12, title="Upload to Digital File Cabinet", status="primary", solidHeader=TRUE,
          div(style="margin-bottom:8px;", strong("Root: "), code(dd2_dir)),
          div(style="margin-bottom:8px;", strong("Next folder (from account): "), textOutput("dd2_preview", inline = TRUE)),
          div(style="margin-bottom:8px;", strong("Last created PDF: "), textOutput("dd2_last", inline = TRUE)),
          checkboxInput("dd2_overwrite", "Overwrite if file exists in DFC", FALSE),
          actionButton("upload_dd2", "Upload to DFC",
                       style = "margin-top:6px; width:180px; background-color:red; color:white; font-weight:bold;"),
          uiOutput("dd2_status")
      )
    ),
    
    tags$img(src = "DETR.png", class = "detr-logo", alt = "DETR logo"),
    tags$div(class = "app-footer", style = "background-color: #003366; color: white; text-align: center; padding: 10px; font-weight : bold",
             HTML("V 6.0 BETA, Created by Eric L. Eakin using the following packages: shiny, shinydashboard, grid, base64enc, png, readr, dplyr"))
  )
)

# =============================================================================
# APP SHELL UI
# =============================================================================
ui <- uiOutput("auth_ui")

# =============================================================================
# SERVER
# =============================================================================
server <- function(input, output, session) {
  
  # --- Auth state ---
  authed <- reactiveVal(FALSE)
  current_user <- reactiveVal(NULL)
  
  output$auth_ui <- renderUI({
    if (isTRUE(authed())) {
      main_app_ui
    } else {
      login_ui()
    }
  })
  
  observeEvent(input$do_login, {
    u <- trimws(req(input$login_user))
    p <- as.character(req(input$login_pass))
    if (auth_ok(u, p, users)) {
      current_user(users[users$username == u & users$password == p, , drop = FALSE])
      authed(TRUE)
      showNotification(sprintf("Welcome, %s.", u), type = "message", duration = 1.2)
    } else {
      showNotification("Invalid username or password.", type = "error", duration = 1.5)
      output$auth_ui <- renderUI(login_ui("Invalid username or password."))
    }
  })
  
  observeEvent(input$do_logout, {
    authed(FALSE)
    current_user(NULL)
    session$sendCustomMessage("clearPasteZone", TRUE)
  })
  
  # --- App state ---
  last_pdf <- reactiveVal(NULL)
  imgs <- reactiveVal(character(0))
  dat_rv <- reactiveVal(ensure_dataset(data_path))
  recent_rv <- reactiveVal(character(0))
  
  # preload NAICS choices on first auth
  observeEvent(authed(), {
    req(authed())
    dat0 <- dat_rv()
    updateSelectizeInput(session, "selA", choices = clean_choices(dat0$Situs), server = TRUE)
    updateSelectizeInput(session, "selB", choices = clean_choices(dat0$Description), server = TRUE)
    updateSelectizeInput(session, "selC", choices = clean_choices(dat0$NAICS), server = TRUE)
    output$add_status <- renderUI(HTML(paste0(
      "<span>Loaded ", nrow(dat0), " rows from <code>", data_path, "</code>.</span>"
    )))
    output$status <- renderText("Waiting to create a PDF...")
  }, once = TRUE)
  
  # Mirror account -> file name
  observeEvent(input$top_text, {
    req(authed())
    d10 <- digits_10(input$top_text)
    if (nzchar(d10)) {
      updateTextInput(session, "file_name", value = paste0("NOTES_", d10, ".pdf"))
    }
  }, ignoreInit = TRUE)
  
  # Keep NAICS choices synced to dataset
  observe({
    req(authed())
    dat <- dat_rv()
    updateSelectizeInput(session, "selA", choices = clean_choices(dat$Situs), server = TRUE)
    updateSelectizeInput(session, "selB", choices = clean_choices(dat$Description), server = TRUE)
    updateSelectizeInput(session, "selC", choices = clean_choices(dat$NAICS), server = TRUE)
  })
  
  # When Description changes, pre-filter NAICS choices
  observeEvent(input$selB, {
    req(authed())
    dat <- dat_rv()
    bval <- trimws(ifelse(is.null(input$selB), "", input$selB))
    c_choices <- clean_choices(dat$NAICS)
    if (nzchar(bval)) {
      idx <- which(!is.na(dat$Description) & trimws(dat$Description) == bval)
      if (length(idx) > 0) {
        mapped <- clean_choices(dat$NAICS[idx])
        if (length(mapped) > 0) c_choices <- mapped
      }
    }
    selected_c <- input$selC
    if (!is.null(selected_c) && selected_c %in% c_choices) {
      # keep
    } else if (length(c_choices) == 1) {
      selected_c <- c_choices[[1]]
    } else {
      selected_c <- NULL
    }
    updateSelectizeInput(session, "selC", choices = c_choices, selected = selected_c, server = TRUE)
  }, ignoreInit = FALSE)
  
  # Build "Situs - Description - NAICS" string
  observe({
    req(authed())
    a <- trimws(ifelse(is.null(input$selA) || !nzchar(input$selA), "", input$selA))
    b <- trimws(ifelse(is.null(input$selB) || !nzchar(input$selB), "", input$selB))
    c <- trimws(ifelse(is.null(input$selC) || !nzchar(input$selC), "", input$selC))
    vals <- c(a, b, c)
    vals <- vals[nzchar(vals)]
    updateTextInput(session, "out_str", value = paste(vals, collapse = " - "))
  })
  
  # Build "Situs - Description" string for QUEST notes
  observeEvent(list(input$selA, input$selB), {
    req(authed())
    a <- trimws(ifelse(is.null(input$selA) || !nzchar(input$selA), "", input$selA))
    b <- trimws(ifelse(is.null(input$selB) || !nzchar(input$selB), "", input$selB))
    val <- paste(c(a, b)[nzchar(c(a, b))], collapse = " - ")
    updateTextInput(session, "situs_desc_input", value = val)
  }, ignoreInit = FALSE)
  
  # Copy feedback & recent copies
  observeEvent(input$copied_situs_desc, {
    req(authed())
    showNotification("Situs - Description copied to clipboard.", type = "message", duration = 1.2)
  })
  observeEvent(input$copied, {
    req(authed())
    showNotification("Copied to clipboard.", type = "message", duration = 1.2)
    copied_txt <- isolate(input$out_str)
    old_txt <- isolate(input$body_text)
    new_txt <- paste(c(old_txt, copied_txt), collapse = ifelse(nzchar(old_txt), "\n", ""))
    updateTextAreaInput(session, "body_text", value = new_txt)
    
    rec <- recent_rv()
    rec <- unique(c(copied_txt, rec))
    if (length(rec) > 5) rec <- rec[1:5]
    recent_rv(rec)
    updateSelectInput(session, "recent_copies", choices = rec, selected = copied_txt)
  })
  observeEvent(input$recent_copies, {
    req(authed())
    val <- input$recent_copies
    if (!is.null(val) && nzchar(val)) updateTextInput(session, "out_str", value = val)
  })
  
  # Clearers
  observeEvent(input$clear_body, {
    req(authed())
    updateTextAreaInput(session, "body_text", value = "")
    showNotification("NAICS & Situs data cleared.", type = "message", duration = 1.5)
  }, ignoreInit = TRUE)
  observeEvent(input$clear_shots, {
    req(authed())
    imgs(character(0))
    session$sendCustomMessage("clearPasteZone", TRUE)
    showNotification("Screenshots cleared.", type = "message", duration = 1.5)
  }, ignoreInit = TRUE)
  observeEvent(input$clear_all, {
    req(authed())
    
    # Also clear the UI Account Number box
    updateTextInput(session, "top_text", value = "")
    
    # Clear NAICS/Situs, Notes, screenshots, and paste zone
    updateTextAreaInput(session, "body_text",  value = "")
    updateTextAreaInput(session, "notes_text", value = "")
    imgs(character(0))
    session$sendCustomMessage("clearPasteZone", TRUE)
    
    showNotification("All data, screenshots, and UI Account Number cleared.", 
                     type = "message", duration = 1.5)
  }, ignoreInit = TRUE)
  
  # --- Image decoding helpers ---
  detect_img_format <- function(path) {
    con <- file(path, "rb"); on.exit(close(con), add = TRUE)
    sig <- readBin(con, what = "raw", n = 8)
    if (length(sig) >= 4 && sig[1]==as.raw(0x89) && sig[2]==as.raw(0x50) && sig[3]==as.raw(0x4E) && sig[4]==as.raw(0x47)) return("png")
    if (length(sig) >= 2 && sig[1]==as.raw(0xFF) && sig[2]==as.raw(0xD8)) return("jpg")
    "unknown"
  }
  read_raster <- function(path){
    fmt <- detect_img_format(path)
    if (fmt == "png") {
      return(grid::rasterGrob(png::readPNG(path), interpolate = TRUE))
    } else if (fmt == "jpg") {
      if (!requireNamespace("jpeg", quietly = TRUE)) return(NULL)
      return(grid::rasterGrob(jpeg::readJPEG(path), interpolate = TRUE))
    } else {
      r <- try(png::readPNG(path), silent = TRUE)
      if (!inherits(r, "try-error")) return(grid::rasterGrob(r, interpolate = TRUE))
      if (requireNamespace("jpeg", quietly = TRUE)) {
        r2 <- try(jpeg::readJPEG(path), silent = TRUE)
        if (!inherits(r2, "try-error")) return(grid::rasterGrob(r2, interpolate = TRUE))
      }
      return(NULL)
    }
  }
  
  # --- PDF generator ---
  # Notes become a 7x5 text panel "slot" like an image, CENTERED TEXT
  make_pdf <- function(header_text, notes_text, footer_text, out_path, image_paths){
    rasters <- lapply(image_paths, read_raster)
    rasters <- rasters[!vapply(rasters, is.null, logical(1))]
    Nimg <- length(rasters)
    
    notes_clean  <- trimws(ifelse(is.null(notes_text), "", notes_text))
    footer_clean <- trimws(ifelse(is.null(footer_text), "", footer_text))
    has_notes <- nzchar(notes_clean)
    
    # total "slots" (image panels + optional notes panel)
    Nslots <- Nimg + if (has_notes) 1L else 0L
    
    page_w <- 8.5; page_h <- 11.0
    img_w_in <- 7.0; img_h_in <- 5.0
    margin_top_in <- 0.5
    margin_bottom_in <- 0.25
    gap_in <- 0.25
    
    footer_left_in  <- 0.5
    footer_y_in     <- 0.20
    footer_width_in <- page_w - footer_left_in - 0.5
    has_gridtext <- requireNamespace("gridtext", quietly = TRUE)
    
    grDevices::pdf(out_path, width = page_w, height = page_h)
    on.exit(dev.off(), add = TRUE)
    
    draw_header <- function() {
      if (nzchar(header_text))
        grid::grid.text(header_text, x = 0.5,
                        y = 1 - margin_top_in/page_h,
                        gp = grid::gpar(fontsize = 14))
    }
    
    prepare_footer <- function() {
      if (!nzchar(footer_clean)) return(NULL)
      if (has_gridtext) {
        tg <- tryCatch(
          gridtext::textbox_grob(
            footer_clean,
            x = grid::unit(footer_left_in, "in"),
            y = grid::unit(footer_y_in, "in"),
            width = grid::unit(footer_width_in, "in"),
            hjust = 0, vjust = 0,
            gp = grid::gpar(cex = 1.0),
            padding = grid::unit(c(0,0,0,0), "pt")
          ),
          error = function(e) {
            gridtext::textbox_grob(
              footer_clean,
              x = grid::unit(footer_left_in, "in"),
              y = grid::unit(footer_y_in, "in"),
              width = grid::unit(footer_width_in, "in"),
              halign = 0, valign = 0,
              gp = grid::gpar(cex = 1.0),
              padding = grid::unit(c(0,0,0,0), "pt")
            )
          }
        )
        h_in <- grid::convertHeight(grid::grobHeight(tg), "in", valueOnly = TRUE)
        reserve_in <- footer_y_in + h_in + 0.05
        list(grob = tg, reserve_in = reserve_in)
      } else {
        chars_per_in <- 12
        wrap_width <- max(10L, floor(chars_per_in * footer_width_in))
        lines <- strwrap(footer_clean, width = wrap_width)
        line_h_in <- 0.18
        h_in <- length(lines) * line_h_in
        reserve_in <- footer_y_in + h_in + 0.05
        tg <- grid::textGrob(
          paste(lines, collapse = "\n"),
          x = grid::unit(footer_left_in, "in"),
          y = grid::unit(footer_y_in, "in"),
          just = "left",
          gp = grid::gpar(cex = 1.0)
        )
        list(grob = tg, reserve_in = reserve_in)
      }
    }
    
    # If no slots at all, but footer text exists → header + footer only
    if (Nslots == 0) {
      grid::grid.newpage(); draw_header()
      ft <- prepare_footer(); if (!is.null(ft)) grid::grid.draw(ft$grob)
      return(invisible())
    }
    
    pages <- ceiling(Nslots / 2)
    slot_idx <- 1L
    
    for (pg in seq_len(pages)) {
      grid::grid.newpage(); draw_header()
      is_last <- (pg == pages)
      footer_info <- if (is_last) prepare_footer() else NULL
      footer_reserve_in <- if (!is.null(footer_info)) footer_info$reserve_in else 0.0
      if (!is.null(footer_info)) grid::grid.draw(footer_info$grob)
      
      left_in <- (page_w - img_w_in) / 2
      n_this <- min(2L, Nslots - slot_idx + 1L)
      
      # First slot on this page (top panel)
      if (n_this >= 1) {
        s <- slot_idx
        y_top <- page_h - margin_top_in - img_h_in
        grid::pushViewport(grid::viewport(
          x = grid::unit(left_in, "in"),
          y = grid::unit(y_top, "in"),
          width  = grid::unit(img_w_in, "in"),
          height = grid::unit(img_h_in, "in"),
          just = c("left","bottom")))
        
        if (s <= Nimg) {
          # screenshot
          grid::grid.draw(rasters[[s]])
        } else {
          # --- NOTES PANEL, CENTERED TEXT (TOP SLOT) ---
          if (nzchar(notes_clean)) {
            if (has_gridtext) {
              tg <- gridtext::textbox_grob(
                notes_clean,
                x      = unit(0.5, "npc"),
                y      = unit(0.5, "npc"),
                width  = unit(0.9, "npc"),
                height = unit(0.9, "npc"),
                halign = 0.5,
                valign = 0.5,
                gp     = gpar(cex = 1.0)
              )
              grid::grid.draw(tg)
            } else {
              lines <- strwrap(notes_clean, width = 80)
              grid::grid.text(
                paste(lines, collapse = "\n"),
                x    = unit(0.5, "npc"),
                y    = unit(0.5, "npc"),
                just = "center",
                gp   = gpar(cex = 1.0)
              )
            }
          }
        }
        grid::popViewport()
        slot_idx <- slot_idx + 1L
      }
      
      # Second slot on this page (bottom panel)
      if (n_this == 2) {
        s <- slot_idx
        y_bottom <- (page_h - margin_top_in - img_h_in) - img_h_in - gap_in
        min_bottom <- margin_bottom_in + footer_reserve_in
        if (y_bottom < min_bottom) y_bottom <- min_bottom
        
        grid::pushViewport(grid::viewport(
          x = grid::unit(left_in, "in"),
          y = grid::unit(y_bottom, "in"),
          width  = grid::unit(img_w_in, "in"),
          height = grid::unit(img_h_in, "in"),
          just = c("left","bottom")))
        
        if (s <= Nimg) {
          grid::grid.draw(rasters[[s]])
        } else {
          # --- NOTES PANEL, CENTERED TEXT (BOTTOM SLOT) ---
          if (nzchar(notes_clean)) {
            if (has_gridtext) {
              tg <- gridtext::textbox_grob(
                notes_clean,
                x      = unit(0.5, "npc"),
                y      = unit(0.5, "npc"),
                width  = unit(0.9, "npc"),
                height = unit(0.9, "npc"),
                halign = 0.5,
                valign = 0.5,
                gp     = gpar(cex = 1.0)
              )
              grid::grid.draw(tg)
            } else {
              lines <- strwrap(notes_clean, width = 80)
              grid::grid.text(
                paste(lines, collapse = "\n"),
                x    = unit(0.5, "npc"),
                y    = unit(0.5, "npc"),
                just = "center",
                gp   = gpar(cex = 1.0)
              )
            }
          }
        }
        grid::popViewport()
        slot_idx <- slot_idx + 1L
      }
    }
  }
  
  # Create PDF
  observeEvent(input$make_pdf, {
    req(authed())
    d10 <- digits_10(input$top_text)
    header_txt <- paste0("NOTES_", if (nzchar(d10)) d10 else "0000000000")
    
    footer_text <- trimws(input$body_text)   # NAICS & Situs footer
    notes_text  <- trimws(input$notes_text)  # Notes panel
    
    fname <- trimws(input$file_name)
    if (!nzchar(fname)) fname <- paste0(header_txt, ".pdf")
    out_path <- file.path(default_dir, sanitize_filename(fname))
    if (file.exists(out_path) && !isTRUE(input$overwrite)) {
      base <- sub("\\.pdf$", "", out_path, ignore.case = TRUE)
      out_path <- paste0(base, "_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".pdf")
    }
    
    ok <- tryCatch({
      make_pdf(header_txt, notes_text, footer_text, out_path, imgs())
      TRUE
    }, error=function(e){
      output$status <- renderText(paste("Error creating PDF:", conditionMessage(e)))
      FALSE
    })
    if (!ok) return()
    
    last_pdf(out_path)
    output$status <- renderText(paste("PDF created at:", out_path))
    try(shell.exec(normalizePath(out_path, winslash="\\", mustWork=FALSE)), silent=TRUE)
  })
  
  output$download_pdf <- downloadHandler(
    filename = function() {
      req(authed())
      lp <- last_pdf()
      if (is.null(lp)) {
        d10 <- digits_10(input$top_text)
        paste0("NOTES_", if (nzchar(d10)) d10 else "0000000000", ".pdf")
      } else basename(lp)
    },
    content = function(file) {
      req(authed())
      lp <- last_pdf()
      if (!is.null(lp) && file.exists(lp)) {
        file.copy(lp, file, overwrite = TRUE)
      } else {
        d10 <- digits_10(input$top_text)
        header_txt <- paste0("NOTES_", if (nzchar(d10)) d10 else "0000000000")
        
        footer_text <- trimws(input$body_text)
        notes_text  <- trimws(input$notes_text)
        
        tmp <- file.path(tempdir(), paste0(header_txt, ".pdf"))
        make_pdf(header_txt, notes_text, footer_text, tmp, imgs())
        file.copy(tmp, file, overwrite = TRUE)
      }
    }
  )
  
  observeEvent(input$open_pdf, {
    req(authed())
    lp <- last_pdf()
    if (!is.null(lp) && file.exists(lp)) {
      try(shell.exec(normalizePath(lp, winslash="\\", mustWork=FALSE)), silent=TRUE)
    } else {
      showNotification("No PDF available yet.", type="warning")
    }
  })
  
  # ---- DFC bits (append logged-in user's first name) ----
  output$dd2_last <- renderText({
    req(authed())
    lp <- last_pdf()
    ts <- if (!is.null(lp) && file.exists(lp)) {
      format(file.info(lp)$mtime, "%Y%m%d_%H%M%S")
    } else {
      format(Sys.time(), "%Y%m%d_%H%M%S")
    }
    uname <- isolate(current_user())$username
    if (!nzchar(uname)) uname <- "User"
    paste0("uploaded_file_", ts, "_", uname)
  })
  
  output$dd2_preview <- renderText({
    req(authed())
    d10 <- digits_10(input$top_text)
    if (!nzchar(d10)) {
      lp <- last_pdf()
      if (!is.null(lp)) {
        b <- basename(lp)
        m <- regexpr("\\d{10}", b)
        if (m[1] > 0) d10 <- substr(b, m[1], m[1] + attr(m, "match.length") - 1)
      }
    }
    if (!nzchar(d10) || nchar(d10) != 10) d10 <- "0000000000"
    segs <- substring(d10, seq(1, 9, by = 2), seq(2, 10, by = 2))
    paste(segs, collapse = .Platform$file.sep)
  })
  
  output$dd2_status <- renderUI(HTML(""))
  
  observeEvent(input$upload_dd2, {
    req(authed())
    lp <- last_pdf()
    if (is.null(lp) || !file.exists(lp)) {
      showNotification("No PDF to upload. Please create a PDF first.", type = "warning", duration = 2)
      output$dd2_status <- renderUI(HTML("<span style='color:#c0392b;'>No PDF to upload.</span>"))
      return()
    }
    
    b <- basename(lp)
    m <- regexpr("\\d{10}", b)
    acct10 <- if (m[1] > 0) substr(b, m[1], m[1] + attr(m, "match.length") - 1) else digits_10(input$top_text)
    if (!nzchar(acct10) || nchar(acct10) != 10) acct10 <- "0000000000"
    
    nested_dir <- nested_2digit_path(dd2_dir, acct10)
    dir.create(nested_dir, showWarnings = FALSE, recursive = TRUE)
    
    ts <- format(file.info(lp)$mtime, "%Y%m%d_%H%M%S")
    uname <- isolate(current_user())$username
    if (!nzchar(uname)) uname <- "User"
    new_name <- paste0("uploaded_file_", ts, "_", uname, ".pdf")
    dest <- file.path(nested_dir, new_name)
    
    if (file.exists(dest) && !isTRUE(input$dd2_overwrite)) {
      dest <- file.path(nested_dir, paste0("uploaded_file_", ts, "_", uname, "_", format(Sys.time(), "%OS3"), ".pdf"))
    }
    
    ok <- tryCatch(file.copy(lp, dest, overwrite = TRUE), error = function(e) FALSE)
    if (ok && file.exists(dest)) {
      rel_nested <- sub(paste0("^", gsub("\\\\", "\\\\\\\\", dd2_dir)), "", normalizePath(nested_dir, winslash="\\", mustWork = FALSE))
      showNotification("Uploaded to DD2 (nested) with renamed file.", type = "message", duration = 1.8)
      output$dd2_status <- renderUI(HTML(paste0(
        "<span style='color:#2e7d32;'>Uploaded to: ",
        sanitize_filename(file.path(rel_nested, new_name)), "</span>"
      )))
    } else {
      showNotification("Failed to upload to DD2.", type = "error", duration = 2)
      output$dd2_status <- renderUI(HTML("<span style='color:#c0392b;'>Failed to upload to DD2 (check permissions or if file is open).</span>"))
    }
  })
  
  # --- Paste handling ---
  observeEvent(input$pasted_image, {
    req(authed())
    data_url <- input$pasted_image
    if (!is.character(data_url) || !nzchar(data_url)) return()
    mime <- sub("^data:([^;]+);base64,.*$", "\\1", data_url, perl = TRUE)
    ext <- switch(tolower(mime),
                  "image/png" = "png", "image/x-png" = "png",
                  "image/jpeg" = "jpg", "image/jpg" = "jpg",
                  "png")
    b64 <- sub("^data:[^;]+;base64,", "", data_url, perl = TRUE)
    raw <- tryCatch(base64enc::base64decode(b64), error=function(e) NULL)
    if (is.null(raw)) return()
    fpath <- file.path(tempdir(), paste0("shot_", format(Sys.time(), "%H%M%S%OS3"), ".", ext))
    writeBin(raw, fpath)
    imgs(c(imgs(), fpath))
  })
  
  # --- Counters / value boxes ---
  shotCount <- reactive(length(imgs()))
  output$shot_count <- renderUI(span(shotCount()))
  outputOptions(output, "shot_count", suspendWhenHidden = FALSE)
  output$shot_box <- renderValueBox({
    req(authed())
    valueBox(shotCount(), "Screenshots Pasted", icon = icon("images"), color = "blue")
  })
  outputOptions(output, "shot_box", suspendWhenHidden = FALSE)
  
  # --- Add row to NAICS dataset ---
  observeEvent(input$add_row, {
    req(authed())
    a <- trimws(ifelse(is.null(input$selA), "", input$selA))
    b <- trimws(ifelse(is.null(input$selB), "", input$selB))
    c <- trimws(ifelse(is.null(input$selC), "", input$selC))
    
    if (!nzchar(a) || !nzchar(b) || !nzchar(c)) {
      output$add_status <- renderUI(
        HTML("<span style='color:#c0392b;'>Please provide values for Situs, Description, and NAICS.</span>")
      )
      return()
    }
    
    dat0 <- isolate(dat_rv())
    new_row <- tibble::tibble(Situs = a, Description = b, NAICS = c)
    dat1 <- dplyr::bind_rows(new_row, dat0) |>
      dplyr::distinct(Situs, Description, NAICS, .keep_all = TRUE)
    
    if (nrow(dat1) == nrow(dat0)) {
      output$add_status <- renderUI(
        HTML("<span style='color:#2c3e50;'>No changes to save (duplicate row ignored).</span>")
      )
      return()
    }
    
    ok <- TRUE
    tryCatch(readr::write_csv(dat1, data_path, na = ""), error = function(e) ok <<- FALSE)
    
    if (!ok) {
      output$add_status <- renderUI(
        HTML("<span style='color:#c0392b;'>Failed to write CSV. Check permissions or if the file is open.</span>")
      )
      return()
    }
    
    dat_rv(dat1)
    updateSelectizeInput(session, "selA", choices = clean_choices(dat1$Situs), server = TRUE)
    updateSelectizeInput(session, "selB", choices = clean_choices(dat1$Description), server = TRUE)
    
    c_choices <- if (nzchar(b)) {
      clean_choices(dat1$NAICS[trimws(dat1$Description) == b])
    } else clean_choices(dat1$NAICS)
    if (length(c_choices) == 0) c_choices <- clean_choices(dat1$NAICS)
    
    sel_c <- input$selC
    if (is.null(sel_c) || !(sel_c %in% c_choices)) sel_c <- NULL
    updateSelectizeInput(session, "selC", choices = c_choices, selected = sel_c, server = TRUE)
    
    output$add_status <- renderUI(
      HTML("<span style='color:#2e7d32;'>Row added and saved.</span>")
    )
  }, ignoreInit = TRUE)
}

shinyApp(ui, server)
