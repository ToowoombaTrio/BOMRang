
#' Get BOM coastal waters forecast
#'
#' Fetch the \acronym{BOM} daily Coastal Waters Forecast and return a data frame
#' of the forecast regions for a specified state or region.
#'
#' @param state Australian state or territory as full name or postal code.
#'  Fuzzy string matching via \code{\link[base]{agrep}} is done.  Defaults to
#'  \dQuote{AUS} returning all state forecasts, see details for further
#'   information.
#'
#' @details Allowed state and territory postal codes, only one state per request
#' or all using \code{AUS}.
#'  \describe{
#'    \item{ACT}{Australian Capital Territory (will return NSW)}
#'    \item{NSW}{New South Wales}
#'    \item{NT}{Northern Territory}
#'    \item{QLD}{Queensland}
#'    \item{SA}{South Australia}
#'    \item{TAS}{Tasmania}
#'    \item{VIC}{Victoria}
#'    \item{WA}{Western Australia}
#'    \item{AUS}{Australia, returns forecast for all states, NT and ACT}
#'  }
#'
#' @return
#' A \code{\link[data.table]{data.table}} of an Australia \acronym{BOM}
#' Coastal Waters Forecast. For full details of fields and units
#' returned see Appendix 5 in the \CRANpkg{bomrang} vignette, use \cr
#' \code{vignette("bomrang", package = "bomrang")} to view.
#'
#' @examples
#' \donttest{
#' coastal_forecast <- get_coastal_forecast(state = "NSW")
#' coastal_forecast
#'}
#' @references
#' Forecast data come from Australian Bureau of Meteorology (BOM) Weather Data
#' Services \cr
#' \url{http://www.bom.gov.au/catalogue/data-feeds.shtml}
#'
#' Location data and other metadata come from the \acronym{BOM} anonymous
#' \acronym{FTP} server with spatial data \cr
#' \url{ftp://ftp.bom.gov.au/anon/home/adfd/spatial/}, specifically the
#' \acronym{DBF} file portion of a shapefile, \cr
#' \url{ftp://ftp.bom.gov.au/anon/home/adfd/spatial/IDM00003.dbf}
#'
#' @author Dean Marchiori, \email{deanmarchiori@@gmail.com} and Paul Melloy
#' \email{paul@@melloy.com.au}
#'
#' @seealso \link{parse_coastal_forecast}
#'
#' @export get_coastal_forecast

get_coastal_forecast <- function(state = "AUS") {
  # this is just a placeholder for functionality with parse_coastal_forecast()
  filepath <- NULL
  # see internal_functions.R for these functions
  the_state <- .check_states(state)
  location <- .validate_filepath(filepath)
  coastal_out <-
    .return_coastal(file_loc = location, cleaned_state = the_state)
  return(coastal_out)
}

# Coastal forecast functions for get() and parse()------------------------------

.return_coastal <- function(file_loc, cleaned_state) {
  # create vector of XML files
  AUS_XML <- c(
    "IDN11001.xml",
    # NSW
    "IDD11030.xml",
    # NT
    "IDQ11290.xml",
    # QLD
    "IDS11072.xml",
    # SA
    "IDT12329.xml",
    # TAS
    "IDV10200.xml",
    # VIC
    "IDW11160.xml"  # WA
  )
  if (cleaned_state != "AUS") {
    xml_url <- .create_bom_file(AUS_XML,
                                .the_state = cleaned_state,
                                .file_loc = file_loc)
    coastal_out <- .parse_coastal_forecast(xml_url)
    if (is.null(coastal_out)) {
      return(invisible(NULL))
    }
    return(coastal_out[])
  } else {
    file_list <- paste0(file_loc, "/", AUS_XML)
    coastal_out <-
      lapply(X = file_list, FUN = .parse_coastal_forecast)
    coastal_out <- data.table::rbindlist(coastal_out, fill = TRUE)
    return(coastal_out[])
  }
}

.parse_coastal_forecast <- function(xml_url) {
  # CRAN note avoidance
  AAC_codes <-
    marine_AAC_codes <- attrs <- end_time_local <- # nocov start
    precipitation_range <-
    start_time_local <- values <- product_id <-
    forecast_swell2 <- forecast_caution <- marine_forecast <-
    state_code <-
    tropical_system_location <-
    forecast_waves <- .SD <- AAC_codes <- NULL # nocov end
  # load the XML from ftp
  if (substr(xml_url, 1, 3) == "ftp") {
    xml_object <- .get_url(xml_url)
    if (is.null(xml_object)) {
      return(invisible(NULL))
    }
  } else {
    # load the XML from local
    xml_object <- xml2::read_xml(xml_url)
  }
  out <- .parse_coastal_xml(xml_object)
  # clean up and split out time cols into offset and remove extra chars
  .split_time_cols(x = out)
  # merge with aac codes for location information
  load(system.file("extdata",
                   "marine_AAC_codes.rda",
                   package = "bomrang"))  # nocov
  data.table::setkey(out, "aac")
  out <- marine_AAC_codes[out, on = c("aac", "dist_name")]
  # add state field
  out[, state_code := gsub("_.*", "", out$aac)]
  # add product ID field
  out[, product_id := substr(basename(xml_url),
                             1,
                             nchar(basename(xml_url)) - 4)]
  # some fields only come out on special occasions, if absent, add as NA
  if (!"forecast_swell2" %in% colnames(out)) {
    out[, forecast_swell2 := NA]
  }
  if (!"forecast_caution" %in% colnames(out)) {
    out[, forecast_caution := NA]
  }
  if (!"marine_forecast" %in% colnames(out)) {
    out[, marine_forecast := NA]
  }
  if (!"tropical_system_location" %in% colnames(out)) {
    out[, tropical_system_location := NA]
  }
  if (!"forecast_waves" %in% colnames(out)) {
    out[, forecast_waves := NA]
  }
  # reorder columns
  refcols <- c(
    "index",
    "product_id",
    "type",
    "state_code",
    "dist_name",
    "pt_1_name",
    "pt_2_name",
    "aac",
    "start_time_local",
    "end_time_local",
    "utc_offset",
    "start_time_utc",
    "end_time_utc",
    "forecast_seas",
    "forecast_weather",
    "forecast_winds",
    "forecast_swell1",
    "forecast_swell2",
    "forecast_caution",
    "marine_forecast",
    "tropical_system_location",
    "forecast_waves"
  )
  data.table::setcolorder(out, refcols)
  # set col classes
  # factors
  out[, c(1, 11) := lapply(.SD, function(x)
    as.factor(x)),
    .SDcols = c(1, 11)]
  out[, c(9:10) := lapply(.SD, function(x)
    as.POSIXct(x,
               origin = "1970-1-1",
               format = "%Y-%m-%d %H:%M:%OS")),
    .SDcols = c(9:10)]
  out[, c(12:13) := lapply(.SD, function(x)
    as.POSIXct(
      x,
      origin = "1970-1-1",
      format = "%Y-%m-%d %H:%M:%OS",
      tz = "GMT"
    )),
    .SDcols = c(12:13)]
  # character
  out[, c(6:8, 14:20) := lapply(.SD, function(x)
    as.character(x)),
    .SDcols = c(6:8, 14:20)]
  return(out)
}

#' extract the values of a coastal forecast item
#'
#' @param xml_object coastal forecast xml_object
#'
#' @return a data.table of the forecast for further refining
#' @keywords internal
#' @author Adam H. Sparks, \email{adamhsparks@@gmail.com}
#' @noRd

.parse_coastal_xml <- function(xml_object) {
  tropical_system_location <-
    forecast_waves <- synoptic_situation <-  # nocov start
    preamble <- warning_summary_footer <- product_footer <-
    postamble <- NULL  # nocov end
  # get the actual forecast objects
  meta <- xml2::xml_find_all(xml_object, ".//text")
  fp <- xml2::xml_find_all(xml_object, ".//forecast-period")
  locations_index <- data.table::data.table(
    # find all the aacs
    aac = xml2::xml_parent(meta) %>%
      xml2::xml_find_first(".//parent::area") %>%
      xml2::xml_attr("aac"),
    # find the names of towns
    dist_name = xml2::xml_parent(meta) %>%
      xml2::xml_find_first(".//parent::area") %>%
      xml2::xml_attr("description"),
    # find corecast period index
    index = xml2::xml_parent(meta) %>%
      xml2::xml_find_first(".//parent::forecast-period") %>%
      xml2::xml_attr("index"),
    start_time_local = xml2::xml_parent(meta) %>%
      xml2::xml_find_first(".//parent::forecast-period") %>%
      xml2::xml_attr("start-time-local"),
    end_time_local = xml2::xml_parent(meta) %>%
      xml2::xml_find_first(".//parent::forecast-period") %>%
      xml2::xml_attr("start-time-local"),
    start_time_utc = xml2::xml_parent(meta) %>%
      xml2::xml_find_first(".//parent::forecast-period") %>%
      xml2::xml_attr("start-time-local"),
    end_time_utc = xml2::xml_parent(meta) %>%
      xml2::xml_find_first(".//parent::forecast-period") %>%
      xml2::xml_attr("start-time-local")
  )
  vals <- lapply(fp, function(node) {
    # find names of all children nodes
    childnodes <- node %>%
      xml2::xml_children() %>%
      xml2::xml_name()
    # find the attr value from all child nodes
    names <- node %>%
      xml2::xml_children() %>%
      xml2::xml_attr("type")
    # create columns names based on either node name or attr value
    names <- ifelse(is.na(names), childnodes, names)
    # find all values
    values <- node %>%
      xml2::xml_children() %>%
      xml2::xml_text()
    # create data frame and properly label the columns
    df <- data.frame(t(values), stringsAsFactors = FALSE)
    names(df) <- names
    df
  })
  vals <- data.table::rbindlist(vals, fill = TRUE)
  sub_out <- cbind(locations_index, vals)
  if ("synoptic_situation" %in% names(sub_out)) {
    sub_out[, synoptic_situation := NULL]
  }
  if ("preamble" %in% names(sub_out)) {
    sub_out[, preamble := NULL]
  }
  if ("warning_summary_footer" %in% names(sub_out)) {
    sub_out[, warning_summary_footer := NULL]
  }
  if ("product_footer" %in% names(sub_out)) {
    sub_out[, product_footer := NULL]
  }
  if ("postamble" %in% names(sub_out)) {
    sub_out[, postamble := NULL]
  }
  return(sub_out)
}
