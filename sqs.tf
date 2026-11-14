# Filas da Saga orquestrada: um consumidor por fila, por isso SQS Standard sem SNS.
# A entrega e pelo menos uma vez e sem ordem garantida; inbox e guarda de estado resolvem nos servicos.
locals {
  filas_saga = toset(["os-saga-eventos", "billing-comandos", "execucao-comandos"])
}

resource "aws_sqs_queue" "saga_dlq" {
  for_each                  = local.filas_saga
  name                      = "${var.project_name}-${each.key}-dlq"
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue" "saga" {
  for_each                   = local.filas_saga
  name                       = "${var.project_name}-${each.key}"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 1209600

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.saga_dlq[each.key].arn
    maxReceiveCount     = 5
  })
}
