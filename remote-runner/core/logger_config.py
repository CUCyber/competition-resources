# core/logger_config.py

import logging
import sys

SUCCESS_LEVEL_NUM = 25
logging.addLevelName(SUCCESS_LEVEL_NUM, "SUCCESS")
setattr(logging, "SUCCESS", SUCCESS_LEVEL_NUM)

def _success_module(msg, *args, **kwargs):
    logging.log(SUCCESS_LEVEL_NUM, msg, *args, **kwargs)

def _success_logger(self, message, *args, **kwargs):
    if self.isEnabledFor(SUCCESS_LEVEL_NUM):
        self._log(SUCCESS_LEVEL_NUM, message, args, **kwargs)

logging.success = _success_module
logging.Logger.success = _success_logger

class CustomFormatter(logging.Formatter):
    gray = "\x1b[38;20m"
    blue = "\x1b[34;20m"
    green = "\x1b[32;20m"
    yellow = "\x1b[33;20m"
    red = "\x1b[31;20m"
    bold_red = "\x1b[31;1m"
    reset = "\x1b[0m"

    fmt = "[%(levelname)s] %(message)s"

    FORMATS = {
        logging.DEBUG: blue + fmt + reset,
        logging.INFO: fmt + reset,
        logging.SUCCESS: green + fmt + reset,
        logging.WARNING: yellow + fmt + reset,
        logging.ERROR: red + fmt + reset,
        logging.CRITICAL: bold_red + fmt + reset
    }

    def format(self, record):
        log_fmt = self.FORMATS.get(record.levelno, self.fmt)
        return logging.Formatter(log_fmt).format(record)

def setup_logging(debug=False, log_file="automation.log"):
    level = logging.DEBUG if debug else logging.INFO
    root = logging.getLogger()
    root.setLevel(level)

    c_handler = logging.StreamHandler(sys.stdout)
    c_handler.setFormatter(CustomFormatter())

    f_handler = logging.FileHandler(log_file)
    f_handler.setFormatter(logging.Formatter("[%(asctime)s] [%(levelname)s] %(message)s", "%Y-%m-%d %H:%M:%S"))

    if not root.handlers:
        root.addHandler(c_handler)
        root.addHandler(f_handler)
