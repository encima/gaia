FROM nikolaik/python-nodejs:python3.11-nodejs21
USER pn
ARG API_URL
WORKDIR /app
COPY --chown=pn . /app
RUN mkdir -p /app/cache
ENV VIRTUAL_ENV=/app/.venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
RUN chown -R pn /app
RUN python3 -m venv $VIRTUAL_ENV
RUN pip install -r requirements.txt
ENV TRANSFORMERS_CACHE=/app/cache
RUN python3 -m reflex db init
RUN reflex init
CMD reflex db migrate && reflex run 
EXPOSE 8000
EXPOSE 3000