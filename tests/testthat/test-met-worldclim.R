## Small rasters laid out like WorldClim's (12 monthly layers per variable), so
## the extraction is tested without a download.
fake_worldclim <- function() {
  skip_if_not_installed("terra")
  layer <- function(values) {
    r <- terra::rast(nrows = 4, ncols = 4, xmin = 130, xmax = 138,
                     ymin = -26, ymax = -18, nlyrs = 12)
    terra::values(r) <- rep(values, each = 16)
    r
  }
  list(rasters = list(
         tmin = layer(seq(20, 9, length.out = 12)),
         tmax = layer(seq(36, 25, length.out = 12)),
         tavg = layer(seq(28, 17, length.out = 12)),
         prec = layer(rep(25, 12)),
         srad = layer(rep(21600, 12)),  # kJ m-2 d-1, so 250 W m-2
         wind = layer(rep(3.5, 12)),
         vapr = layer(rep(1, 12))),
       elevation = { e <- terra::rast(nrows = 4, ncols = 4, xmin = 130, xmax = 138,
                                      ymin = -26, ymax = -18); terra::values(e) <- 550; e })
}

test_that("WorldClim layers become monthly columns in met_from_monthly's units", {
  f <- fake_worldclim()
  m <- worldclim_extract(f$rasters, f$elevation, -22.28, 133.25)
  expect_identical(m$month, 1:12)
  expect_equal(m$SWdown_mean, rep(250, 12))
  expect_equal(m$Tair_max, seq(36, 25, length.out = 12))
  expect_identical(attr(m, "elevation"), 550)
  expect_identical(attr(m, "climatology_of"), c(1970L, 2000L))
  met <- met_from_monthly(m, -22.28, 133.25, elevation = attr(m, "elevation"))
  expect_equal(sum(met$Precip), 300)
})

test_that("a site off the grid is refused", {
  f <- fake_worldclim()
  expect_error(worldclim_extract(f$rasters, f$elevation, -40, 150), "no value")
})

test_that("an unsupported resolution is refused before any download", {
  skip_if_not_installed("geodata")
  expect_error(worldclim_monthly(0, 0, res = 1), "10, 5, 2.5 or 0.5")
})
