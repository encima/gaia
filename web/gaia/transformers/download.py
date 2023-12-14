from transformers import BertTokenizer, BertModel

tokenizer = BertTokenizer.from_pretrained("bert-base-uncased")
tokenizer.save_pretrained('./web/gaia/transformers/bert-base-uncased-tokenizer')
model = BertModel.from_pretrained("bert-base-uncased")
model.save_pretrained('./web/gaia/transformers/bert-base-uncased-model')