FROM r-base:latest

WORKDIR /rplumber
COPY . /rplumber

RUN R -e 'install.packages("plumber", repos = "https://cloud.r-project.org")'
RUN echo 'library(plumber)' > /rplumber/.Rprofile
RUN R_DEFAULT_PACKAGES=plumber

EXPOSE 8000

CMD R -e '(r <- plumb("/rplumber/plumber.R")) & (r$run(host="0.0.0.0", port=8000))'
