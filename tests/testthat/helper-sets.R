## A copy of the test set with the installed plant's model version written in,
## and its met file beside it, so the set is current whatever plant is
## installed. `edit` changes the YAML text before it is written.
test_set <- function(edit = identity, model = "TF24") {
  dir <- withr::local_tempdir(.local_envir = parent.frame())
  text <- readLines(test_path("fixtures", "sets", "tf24_test.yml"))
  text <- sub("@PLANT_VERSION@", plant::model_id(model), text, fixed = TRUE)
  text <- edit(text)
  writeLines(text, file.path(dir, "tf24_test.yml"))
  file.copy(test_path("fixtures", "sets", "test_met.csv"), dir)
  file.path(dir, "tf24_test.yml")
}
